//
//  NativeFullScreenStyleMapping.swift
//  MobileAdsClient
//
//  Translates a caller's close-gate request into the renderer's configuration.
//

#if canImport(UIKit)
import MobileAdsClient
import NativeAdClient

extension NativeAdClient.Configuration.FullScreen {
    /// Builds a full-screen configuration from a caller's close-gate request.
    ///
    /// This is the one place the two vocabularies meet: `MobileAdsClient` states
    /// what a caller wants without depending on `NativeAdClient`, and this target
    /// — the only one that sees both — turns it into the renderer's config.
    ///
    /// `nil` yields `.default`, which is what the presenter used before a caller
    /// could ask for anything.
    static func applying(_ style: MobileAdsClient.NativeFullScreenStyle?) -> Self {
        guard let style else {
            return .default
        }
        var configuration = Self.default
        configuration.closeCountdown = style.closeCountdownSeconds
        configuration.closeHitSlop = style.closeHitSlop
        return configuration
    }
}
#endif
