//
//  RewardedAdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
import AdRevenueClient
import GoogleMobileAds
import MobileAdsClient
import os

final internal class RewardedAdManager: BaseAdManager<RewardedAd> {
    override var format: AdRevenueEvent.AdFormat { .rewarded }

    /// Captures whether `userDidEarnRewardHandler` fired before dismiss for a
    /// given ad unit. Read and cleared by `showAndAwaitReward`. Uses
    /// `OSAllocatedUnfairLock` (not `NSLock`) because Swift 6 strict
    /// concurrency disallows `NSLock.lock/unlock` from async contexts;
    /// `withLock { … }` is async-safe and scoped.
    private let pendingReward = OSAllocatedUnfairLock<[String: Bool]>(initialState: [:])

    override func loadAd(adUnitID: String) async throws -> RewardedAd {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RewardedAd, Error>) in
            let request = Request()
            RewardedAd.load(with: adUnitID, request: request) { [weak self] ad, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let ad = ad {
                    ad.fullScreenContentDelegate = self
                    self?.attachPaidEventHandler(ad, adUnitID: adUnitID)
                    continuation.resume(returning: ad)
                }
            }
        }
    }

    override func adTypeName() -> String {
        "REWARDED"
    }

    @MainActor
    override func presentAd(_ ad: RewardedAd, from viewController: UIViewController) {
        ad.present(from: viewController) {
            // The real reward-earn path flows through `showAndAwaitReward`,
            // which installs its own handler via `present(from:)`. This
            // override only exists so the generic `BaseAdManager.showAd`
            // path (void-returning) also compiles for rewarded ads.
        }
    }

    /// Presents the rewarded ad and resumes with `true` if the user earned
    /// the reward before dismiss, `false` otherwise. Uses `BaseAdManager`'s
    /// cache + `FullScreenContentDelegate` plumbing for the dismiss signal;
    /// the reward-earn signal is captured separately via
    /// `userDidEarnRewardHandler`.
    @MainActor
    func showAndAwaitReward(_ adUnitID: String, from viewController: UIViewController) async throws -> Bool {
        guard let ad = getAd(for: adUnitID) else {
            throw MobileAdsClient.AdError.adNotReady
        }

        pendingReward.withLock { $0[adUnitID] = false }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setContinuation(continuation, for: adUnitID)
            ad.present(from: viewController) { [weak self] in
                self?.pendingReward.withLock { $0[adUnitID] = true }
            }
        }

        return pendingReward.withLock { $0.removeValue(forKey: adUnitID) ?? false }
    }
}

extension RewardedAd: @retroactive @unchecked Sendable {

}
#endif
