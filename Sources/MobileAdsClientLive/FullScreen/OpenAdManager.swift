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

    #if MOBILEADS_GOOGLE_PRELOAD
        import GoogleMobileAds_Private
    #endif

    final internal class OpenAdManager: BaseAdManager<AppOpenAd>, @unchecked Sendable {
        override var format: AdRevenueEvent.AdFormat { .appOpen }

        /// App-open ads expire ~4h after load; keep the pooled TTL comfortably
        /// under that so a served ad is always presentable.
        override var poolMaxAge: TimeInterval { 14000 }  // ~3.9 hours

        override func loadAd(
            adUnitID: String,
            keywords: [String]
        ) async throws -> AppOpenAd {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppOpenAd, Error>) in
                let request = Request()
                request.keywords = keywords
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
        override func presentAd(
            _ ad: AppOpenAd,
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
                return AppOpenAdPreloader.shared.preload(
                    for: preloadID,
                    configuration: configuration,
                    delegate: self
                )
            }

            override func googleIsAvailable(_ preloadID: String) -> Bool {
                AppOpenAdPreloader.shared.isAdAvailable(with: preloadID)
            }

            override func googleAdCount(_ preloadID: String) -> Int {
                Int(AppOpenAdPreloader.shared.numberOfAdsAvailable(with: preloadID))
            }

            override func googleDequeue(_ preloadID: String) -> AppOpenAd? {
                AppOpenAdPreloader.shared.ad(with: preloadID)  // dequeue + auto-refill
            }

            override func googleStop(_ preloadID: String) {
                AppOpenAdPreloader.shared.stopPreloadingAndRemoveAds(for: preloadID)
            }
        #endif
    }

    // MARK: - PreloadDelegate

    #if MOBILEADS_GOOGLE_PRELOAD
        extension OpenAdManager: PreloadDelegate {
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

    extension AppOpenAd: @retroactive @unchecked Sendable {

    }
#endif
