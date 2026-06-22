//
//  InterstitialAdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 4/2/25.
//

#if canImport(UIKit)
    import AdRevenueClient
    import GoogleMobileAds
    import MobileAdsClient

    final internal class InterstitialAdManager: BaseAdManager<InterstitialAd> {
        override var format: AdRevenueEvent.AdFormat { .interstitial }

        override func loadAd(
            adUnitID: String,
            keywords: [String]
        ) async throws -> InterstitialAd {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InterstitialAd, Error>) in
                let request = Request()
                request.keywords = keywords
                InterstitialAd.load(with: adUnitID, request: request) { [weak self] ad, error in
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
            "INTERSTITIAL"
        }

        @MainActor
        override func presentAd(
            _ ad: InterstitialAd,
            from viewController: UIViewController
        ) {
            ad.present(from: viewController)
        }
    }

    extension InterstitialAd: @retroactive @unchecked Sendable {

    }
#endif
