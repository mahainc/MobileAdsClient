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

    #if MOBILEADS_GOOGLE_PRELOAD
        import GoogleMobileAds_Private
    #endif

    final internal class InterstitialAdManager: BaseAdManager<InterstitialAd>, @unchecked Sendable {
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

        // MARK: - Google Preloader bridges

        #if MOBILEADS_GOOGLE_PRELOAD
            override var supportsGooglePreload: Bool { true }

            override func googleRegister(
                _ preloadID: String,
                bufferSize: Int
            ) -> Bool {
                let configuration = PreloadConfigurationV2(adUnitID: preloadID, request: Request())
                configuration.bufferSize = UInt(bufferSize)
                return InterstitialAdPreloader.shared.preload(
                    for: preloadID,
                    configuration: configuration,
                    delegate: self
                )
            }

            override func googleIsAvailable(_ preloadID: String) -> Bool {
                InterstitialAdPreloader.shared.isAdAvailable(with: preloadID)
            }

            override func googleDequeue(_ preloadID: String) -> InterstitialAd? {
                InterstitialAdPreloader.shared.ad(with: preloadID)  // dequeue + auto-refill
            }

            override func googleStop(_ preloadID: String) {
                InterstitialAdPreloader.shared.stopPreloadingAndRemoveAds(for: preloadID)
            }
        #endif
    }

    // MARK: - PreloadDelegate

    #if MOBILEADS_GOOGLE_PRELOAD
        extension InterstitialAdManager: PreloadDelegate {
            func adAvailable(
                forPreloadID preloadID: String,
                responseInfo: ResponseInfo
            ) {
                logPool("preload: ad available · unit=\(preloadID)")
            }

            func adsExhausted(forPreloadID preloadID: String) {
                logPool("preload: EXHAUSTED · unit=\(preloadID)")
            }

            func adFailedToPreload(
                forPreloadID preloadID: String,
                error: Error
            ) {
                logPool("preload: FAILED · unit=\(preloadID) · error=\(error.localizedDescription)")
            }
        }
    #endif

    extension InterstitialAd: @retroactive @unchecked Sendable {

    }
#endif
