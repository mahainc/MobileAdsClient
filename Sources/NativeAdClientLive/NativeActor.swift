//
//  NativeActor.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 13/2/25.
//

#if canImport(UIKit)
    @preconcurrency import GoogleMobileAds
    import NativeAdClient

    final internal actor NativeActor {

        private let manager = NativeAdManager()

        public init() {}
    }

    // MARK: - Public Methods

    extension NativeActor {

        public func loadAd(
            adUnitID: String,
            from viewController: UIViewController?,
            options: [NativeAdClient.AnyAdLoaderOption]?,
            keywords: [String] = [],
            featureID: String = ""
        ) async throws -> NativeAd {
            return try await manager.loadAd(
                adUnitID: adUnitID,
                from: viewController,
                options: options,
                keywords: keywords,
                featureID: featureID
            )
        }

        public func loadAds(
            adUnitID: String,
            from viewController: UIViewController?,
            options: [NativeAdClient.AnyAdLoaderOption]?,
            count: Int,
            keywords: [String] = [],
            featureID: String = ""
        ) async throws -> [NativeAd] {
            return try await manager.loadAds(
                adUnitID: adUnitID,
                from: viewController,
                options: options,
                count: count,
                keywords: keywords,
                featureID: featureID
            )
        }
    }
#endif
