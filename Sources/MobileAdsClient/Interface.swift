//
//  MobileAdsClient Interface
//  A dependency-injectable wrapper for Google Mobile Ads (full-screen, rewarded,
//  and full-screen native presentation).
//

import ComposableArchitecture

// MARK: - MobileAdsClient

/// Flat dependency surface for showing ads. Full-screen (interstitial / app-open),
/// rewarded, and full-screen native each get their own verb-first endpoint.
///
/// Preloading is split into two intents:
/// - `warmFullScreenAd` — on-demand, keyword-aware, served from the hand-rolled pool.
/// - `registerPreloads` / `stopPreloading` — eager, SDK-buffered (Google Preloader),
///   keyword-less. The host registers once after bootstrap; the SDK keeps the buffer
///   full and fresh. `stopPreloading` sheds buffers (e.g. premium users).
@DependencyClient
public struct MobileAdsClient: Sendable {
    /// Historically registered a paid-event bridge for the legacy ads_swift
    /// `AdRevenueDelegate`. Now a no-op: every ad format attaches its own
    /// `paidEventHandler` at load time (see `BaseAdManager.attachPaidEventHandler`
    /// and `NativeAdManager.adLoader(_:didReceive:)`). Kept on the interface so
    /// `AdsBootstrap.installingRevenueBridge` still calls through.
    public var installRevenueBridge: @Sendable () async -> Void

    /// Gate: whether a full-screen ad of `adType` should be shown given `rules` and
    /// contextual `keywords`.
    public var shouldShowFullScreenAd:
        @Sendable (_ adType: AdType, _ rules: [AdRule], _ keywords: [String]) async -> Bool = { _, _, _ in false }

    /// Presents a full-screen ad (`interstitial` / `appOpen`) for `adType`.
    public var showFullScreenAd: @Sendable (_ adType: AdType, _ keywords: [String]) async throws -> Void

    /// Warms the keyword-aware pool for `adType` so a subsequent `showFullScreenAd`
    /// presents without a load delay. Caller resolves the unit ID upstream.
    /// Google-managed (registered, keyword-less) units no-op here — the SDK owns
    /// that buffer.
    public var warmFullScreenAd: @Sendable (_ adType: AdType, _ keywords: [String]) async -> Void

    /// Eagerly registers keyword-less units with Google's Preloader. Call once
    /// after `MobileAdsBootstrap.start()`. Keep the list curated and `bufferSize`
    /// small (2–3) — Google caps total preloaded ads (~6 app-wide) and unshown
    /// preloaded ads dilute show rate.
    public var registerPreloads: @Sendable (_ adTypes: [AdType], _ bufferSize: Int) async -> Void

    /// Stops preloading and drops the SDK buffer for the given units.
    public var stopPreloading: @Sendable (_ adTypes: [AdType]) async -> Void

    /// Presents a rewarded ad for `unitID` and resumes with `true` if the user
    /// earned the reward, `false` if they dismissed without earning or the show
    /// failed. Caller decides whether to grant the reward when ads are off or the
    /// load fails.
    public var showRewardedAd: @Sendable (_ unitID: String, _ keywords: [String]) async -> Bool = { _, _ in false }

    /// A fresh stream of show-time load states (`.loading` / `.ready` / `.failed`),
    /// so a host can present a spinner while `showFullScreenAd` fetches an ad it
    /// couldn't serve from cache. Emits **only** for show-time cold loads (and the
    /// native on-demand load) — background `warmFullScreenAd` and Google preload
    /// refills are silent. Each call returns an independent stream; subscribe once
    /// and drive UI from the emitted `AdType`.
    public var loadStates: @Sendable () -> AsyncStream<AdLoadState> = { AsyncStream { $0.finish() } }

    /// A point-in-time snapshot of currently-available preloaded ads: Google
    /// Preloader bucket counts + `AdPool` variants, per unit. Buffers refill
    /// asynchronously in the SDK/pool, so treat this as a reading, not a live value —
    /// call it when you need one (debug overlay, telemetry).
    public var preloadStatus: @Sendable () async -> PreloadStatus = { PreloadStatus() }
}
