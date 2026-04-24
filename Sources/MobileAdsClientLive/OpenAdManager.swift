//
//  OpenAdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
import AdRevenueClient
import GoogleMobileAds
import MobileAdsClient

final internal class OpenAdManager: BaseAdManager<AppOpenAd> {
    override var format: AdRevenueEvent.AdFormat { .appOpen }

    override func loadAd(adUnitID: String) async throws -> AppOpenAd {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppOpenAd, Error>) in
            let request = Request()
            AppOpenAd.load(with: adUnitID, request: request) { [weak self] ad, error in
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
        "APP_OPEN"
    }

    @MainActor
    override func presentAd(_ ad: AppOpenAd, from viewController: UIViewController) {
        ad.present(from: viewController)
    }
}

extension AppOpenAd: @retroactive @unchecked Sendable {

}
#endif
