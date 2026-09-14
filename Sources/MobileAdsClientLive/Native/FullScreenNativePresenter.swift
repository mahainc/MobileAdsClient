//
//  FullScreenNativePresenter.swift
//  MobileAdsClient
//
//  Loads a native ad via `NativeAdClient` (or takes one `NativeFullScreenPreloads`
//  already holds), attaches a `paidEventHandler` that publishes through
//  `AdRevenueClient`, and presents `FullScreenNativeView` in a
//  `UIHostingController` on the top view controller. Wiring lives here so
//  `Live.swift` only holds the closure that delegates in.
//

#if canImport(UIKit)
import ComposableArchitecture
import MobileAdsClient
import MobileAdsClientUI
import NativeAdClient
import NativeAdClientLive
import SwiftUI
import UIKit
@preconcurrency import GoogleMobileAds

enum FullScreenNativePresenter {
    /// How long a native load waits for the host to start the SDK before giving up.
    /// Past it the show fails instead of holding a gate open indefinitely.
    static var sdkStartTimeout: Duration { .seconds(10) }

    static func present(
        adUnitID: String,
        keywords: [String] = [],
        featureID: String = "",
        slotRef: String = "",
        configuration: FullScreenNativeAdView.Configuration = .default,
        adChoicesCorner: NativeAdClient.AdChoicesPositionOption.Corner = .bottomLeft,
        mediaAspectRatio: NativeAdClient.MediaAspectRatioOption.Ratio? = nil,
        videoStartsMuted: Bool = true,
        onColdLoad: (@Sendable (AdLoadPhase) -> Void)? = nil
    ) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                let resumeBox = ResumeOnce()

                guard let topVC = UIApplication.shared.topViewController() else {
                    resumeBox.resume(continuation, didShow: false)
                    return
                }

                let request = ShowRequest(
                    adUnitID: adUnitID,
                    keywords: keywords,
                    requester: MobileAdsClient.AdRequester(featureID: featureID, slotRef: slotRef),
                    options: loaderOptions(
                        adChoicesCorner: adChoicesCorner,
                        mediaAspectRatio: mediaAspectRatio,
                        videoStartsMuted: videoStartsMuted
                    )
                )
                // Load before presenting so the user never sees a blank screen
                // with a spinner. If the load fails, resume immediately.
                guard let nativeAd = await adToPresent(for: request, from: topVC, onColdLoad: onColdLoad) else {
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

                let host = UIHostingController(rootView: content.ignoresSafeArea())
                host.modalPresentationStyle = .fullScreen
                host.loadViewIfNeeded()
                host.view.frame = hostVC.view.bounds
                host.view.applyBackgroundFill(configuration.style.backgrounds.card)
                hostVC.present(host, animated: true)
                // An accepted present links the two controllers immediately. UIKit
                // refuses one from a controller that is already presenting or
                // mid-dismiss — without calling a completion — and then `onClose`
                // can never run.
                if host.presentingViewController == nil {
                    resumeBox.resume(continuation, didShow: false)
                }
            }
        }
    }

    /// Loader options for the full-screen layout. AdChoices defaults to the
    /// bottom-left: with full-bleed media a top corner puts it under the status
    /// bar / Dynamic Island (the AdMob validator flags it as obstructed), and the
    /// close button / countdown sit top-right. Video starts muted by default.
    static func loaderOptions(
        adChoicesCorner: NativeAdClient.AdChoicesPositionOption.Corner = .bottomLeft,
        mediaAspectRatio: NativeAdClient.MediaAspectRatioOption.Ratio? = nil,
        videoStartsMuted: Bool = true
    ) -> [NativeAdClient.AnyAdLoaderOption] {
        var options: [NativeAdClient.AnyAdLoaderOption] = [
            .init(NativeAdClient.AdChoicesPositionOption(corner: adChoicesCorner)),
            .init(NativeAdClient.VideoPlaybackOption(shouldStartMuted: videoStartsMuted)),
        ]
        if let mediaAspectRatio {
            options.append(.init(NativeAdClient.MediaAspectRatioOption(ratio: mediaAspectRatio)))
        }
        return options
    }

    private struct ShowRequest {
        let adUnitID: String
        let keywords: [String]
        let requester: MobileAdsClient.AdRequester
        let options: [NativeAdClient.AnyAdLoaderOption]
    }

    /// The ad to present: a held preload for a keyword-less request, rebound to
    /// this show's feature and slot; otherwise a show-time load, which reports
    /// through `onColdLoad`. Nil when neither produced an ad.
    @MainActor
    private static func adToPresent(
        for request: ShowRequest,
        from viewController: UIViewController,
        onColdLoad: (@Sendable (AdLoadPhase) -> Void)?
    ) async -> NativeAd? {
        if request.keywords.isEmpty, let preloaded = await NativeFullScreenPreloads.shared.take(request.adUnitID) {
            preloaded.publishPaidEvents(adUnitID: request.adUnitID, format: .native, requester: request.requester)
            return preloaded
        }
        guard await MobileAdsBootstrap.awaitReady(timeout: sdkStartTimeout) else {
            return nil
        }

        @Dependency(\.nativeAdClient) var nativeAdClient
        onColdLoad?(.started)
        do {
            // `NativeAdManager.adLoader(_:didReceive:)` attaches the
            // `paidEventHandler`, so revenue flows without extra wiring.
            let nativeAd = try await nativeAdClient.loadAd(
                request.adUnitID,
                viewController,
                request.options,
                request.keywords,
                request.requester.featureID,
                request.requester.slotRef
            )
            onColdLoad?(.ready)
            return nativeAd
        } catch {
            onColdLoad?(.failed)
            #if DEBUG
            print(
                "[FullScreenNativePresenter] load failed adUnit=\(request.adUnitID) error=\(error.localizedDescription)"
            )
            #endif
            return nil
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
