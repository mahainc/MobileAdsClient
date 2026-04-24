//
//  BaseAdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 11/6/25.
//

#if canImport(UIKit)
import AdRevenueClient
import ComposableArchitecture
import GoogleMobileAds
import MobileAdsClient

/// Ad types that expose `paidEventHandler`. `InterstitialAd`, `AppOpenAd`, and
/// `RewardedAd` all match this shape; used by `BaseAdManager` to attach a shared
/// revenue publisher at load time without subclass-specific glue.
protocol PaidEventCapable: AnyObject {
    var paidEventHandler: ((AdValue) -> Void)? { get set }
}

extension InterstitialAd: PaidEventCapable {}
extension AppOpenAd: PaidEventCapable {}
extension RewardedAd: PaidEventCapable {}

/// Generic base class for managing full-screen ads with thread-safe operations.
/// Subclasses must override `loadAd(adUnitID:)`, `adTypeName()`, and set `format`
/// to the matching `AdRevenueEvent.AdFormat` so paid-event revenue is published
/// with the correct classification.
class BaseAdManager<AdType: FullScreenPresentingAd>: NSObject, FullScreenContentDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var ads: [String: AdType] = [:]
    private var dismissContinuations: [String: CheckedContinuation<Void, Error>] = [:]

    /// Set by each subclass; threaded through the paid-event publisher so Adjust
    /// + Analytics can distinguish app-open vs interstitial vs rewarded revenue.
    var format: AdRevenueEvent.AdFormat { .interstitial }

    // MARK: - Thread-Safe Accessors

    final func getAd(for adUnitID: String) -> AdType? {
        lock.lock()
        defer { lock.unlock() }
        return ads[adUnitID]
    }

    final func setAd(_ ad: AdType, for adUnitID: String) {
        lock.lock()
        defer { lock.unlock() }
        ads[adUnitID] = ad
    }

    final func removeAd(for adUnitID: String) {
        lock.lock()
        defer { lock.unlock() }
        ads.removeValue(forKey: adUnitID)
    }

    final func setContinuation(_ continuation: CheckedContinuation<Void, Error>, for adUnitID: String) {
        lock.lock()
        defer { lock.unlock() }
        dismissContinuations[adUnitID] = continuation
    }

    final func removeContinuation(for adUnitID: String) -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return dismissContinuations.removeValue(forKey: adUnitID)
    }

    final func findAdUnitID(for ad: FullScreenPresentingAd) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return ads.first(where: { $0.value === ad })?.key
    }

    // MARK: - Revenue attribution

    /// Attaches a paid-event handler to a freshly loaded ad. The handler forwards
    /// every paid impression to `AdRevenueClient.publish` with the subclass's
    /// `format`. Subclasses call this in `loadAd(adUnitID:)` right before handing
    /// the loaded ad back to the continuation.
    final func attachPaidEventHandler(_ ad: PaidEventCapable, adUnitID: String) {
        let format = self.format
        ad.paidEventHandler = { adValue in
            @Dependency(\.adRevenueClient) var adRevenueClient
            adRevenueClient.publish(AdRevenueEvent(
                amount: Double(truncating: adValue.value),
                currency: adValue.currencyCode,
                adUnitId: adUnitID,
                format: format,
                source: .googleMobileAds,
                receivedAt: .now
            ))
        }
    }

    // MARK: - Abstract Methods (Override in subclass)

    /// Loads an ad for the specified ad unit ID. Subclasses must override this method.
    /// - Parameter adUnitID: The ad unit ID to load
    /// - Returns: The loaded ad instance
    /// - Throws: Error if ad loading fails
    func loadAd(adUnitID: String) async throws -> AdType {
        fatalError("Subclass must override loadAd(adUnitID:)")
    }

    /// Returns the name of the ad type for logging purposes. Subclasses must override this method.
    /// - Returns: A string representing the ad type (e.g., "APP_OPEN", "INTERSTITIAL", "REWARDED")
    func adTypeName() -> String {
        fatalError("Subclass must override adTypeName()")
    }

    /// Presents the ad. Subclasses must override this method to call the appropriate present method for their ad type.
    /// - Parameters:
    ///   - ad: The ad to present
    ///   - viewController: The view controller to present from
    @MainActor
    func presentAd(_ ad: AdType, from viewController: UIViewController) {
        fatalError("Subclass must override presentAd(_:from:)")
    }

    // MARK: - Public Methods

    /// Checks if an ad should be shown based on rules, loading if necessary.
    /// - Parameters:
    ///   - adUnitID: The ad unit ID
    ///   - rules: Rules to evaluate before showing the ad
    /// - Returns: True if the ad should be shown, false otherwise
    public final func shouldShowAd(_ adUnitID: String, rules: [MobileAdsClient.AdRule]) async -> Bool {
        let isSatisfied = await rules.allRulesSatisfied()

        if getAd(for: adUnitID) == nil {
            do {
                let ad = try await loadAd(adUnitID: adUnitID)
                setAd(ad, for: adUnitID)
                #if DEBUG
                print("🍺 \(adTypeName()) ad loaded successfully")
                #endif
                return isSatisfied
            } catch {
                #if DEBUG
                print("🌶️ Failed to load \(adTypeName()) ad: \(error.localizedDescription)")
                #endif
                return false
            }
        }

        return isSatisfied
    }

    /// Shows the ad for the specified ad unit ID.
    /// - Parameters:
    ///   - adUnitID: The ad unit ID
    ///   - viewController: The view controller to present from
    /// - Throws: `MobileAdsClient.AdError.adNotReady` if the ad is not loaded
    @MainActor
    public final func showAd(_ adUnitID: String, from viewController: UIViewController) async throws {
        guard let ad = getAd(for: adUnitID) else {
            throw MobileAdsClient.AdError.adNotReady
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setContinuation(continuation, for: adUnitID)
            presentAd(ad, from: viewController)
        }
    }

    // MARK: - FullScreenContentDelegate

    @objc
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard let adUnitID = findAdUnitID(for: ad) else { return }

        removeContinuation(for: adUnitID)?.resume(returning: ())

        Task {
            do {
                let loadedAd = try await loadAd(adUnitID: adUnitID)
                setAd(loadedAd, for: adUnitID)
            } catch {
                // Silently fail - ad will be reloaded on next shouldShowAd call
            }
        }
    }

    @objc
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        guard let adUnitID = findAdUnitID(for: ad) else { return }

        removeContinuation(for: adUnitID)?.resume(throwing: error)
    }
}
#endif
