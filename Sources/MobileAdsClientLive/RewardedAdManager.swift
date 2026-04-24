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

final internal class RewardedAdManager: BaseAdManager<RewardedAd> {
    override var format: AdRevenueEvent.AdFormat { .rewarded }

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
            // Reward callback can be handled here if needed
        }
    }
}

extension RewardedAd: @retroactive @unchecked Sendable {

}
#endif
