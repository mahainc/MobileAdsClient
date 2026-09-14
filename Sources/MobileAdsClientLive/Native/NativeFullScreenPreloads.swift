#if canImport(UIKit)
import ComposableArchitecture
import Foundation
import NativeAdClient
import NativeAdClientLive
@preconcurrency import GoogleMobileAds

/// At most one loaded native ad per unit, held for `FullScreenNativePresenter`.
///
/// Lets a caller that asks "is this native unit ready?" get an answer backed by a
/// real load, and lets the show that follows present that ad instead of loading
/// again. Only keyword-less requests use it, because the held ad was loaded
/// without keywords.
actor NativeFullScreenPreloads {
    static let shared = NativeFullScreenPreloads()

    /// Google native ads expire an hour after loading; stop serving a little sooner.
    private static var maxAge: TimeInterval { 3300 }

    private struct Preload {
        let ad: NativeAd
        let loadedAt: Date

        var isFresh: Bool {
            Date.now.timeIntervalSince(loadedAt) < NativeFullScreenPreloads.maxAge
        }
    }

    private var preloads: [String: Preload] = [:]
    private var loads: [String: Task<Bool, Never>] = [:]

    /// Returns whether a fresh ad is held for `adUnitID`, loading one if needed.
    /// A call made while a load is running joins that load.
    func warm(_ adUnitID: String) async -> Bool {
        if preloads[adUnitID]?.isFresh == true {
            return true
        }
        if let running = loads[adUnitID] {
            return await running.value
        }
        let load = Task { await loadPreload(adUnitID) }
        loads[adUnitID] = load
        let isReady = await load.value
        loads[adUnitID] = nil
        return isReady
    }

    /// Hands over the held ad for `adUnitID` if it is still fresh. The caller owns
    /// it from here, so the next `warm` loads a replacement.
    func take(_ adUnitID: String) -> NativeAd? {
        guard let preload = preloads.removeValue(forKey: adUnitID), preload.isFresh else {
            return nil
        }
        return preload.ad
    }

    private func loadPreload(_ adUnitID: String) async -> Bool {
        guard await MobileAdsBootstrap.awaitReady(timeout: FullScreenNativePresenter.sdkStartTimeout) else {
            return false
        }
        @Dependency(\.nativeAdClient) var nativeAdClient
        do {
            let ad = try await nativeAdClient.loadAd(adUnitID, nil, FullScreenNativePresenter.loaderOptions())
            preloads[adUnitID] = Preload(ad: ad, loadedAt: .now)
            return true
        } catch {
            #if DEBUG
            print("[NativeFullScreenPreloads] preload failed adUnit=\(adUnitID) error=\(error.localizedDescription)")
            #endif
            return false
        }
    }
}
#endif
