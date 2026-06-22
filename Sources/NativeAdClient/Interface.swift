//
//  NativeAdClient.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 13/2/25.
//

import DependenciesMacros

#if canImport(UIKit)
    import GoogleMobileAds
    import UIKit

    @DependencyClient
    public struct NativeAdClient: Sendable {
        public var loadAd:
            @Sendable (
                _ adUnitID: String, _ rootViewController: UIViewController?,
                _ options: [NativeAdClient.AnyAdLoaderOption]?, _ keywords: [String]
            ) async throws -> NativeAd
        /// Batch fetch up to `count` native ads in a single auction via
        /// `MultipleAdsAdLoaderOptions`. Returns whatever ads landed before the
        /// SDK reported completion / failure / timeout — empty array is valid.
        public var loadAds:
            @Sendable (
                _ adUnitID: String, _ rootViewController: UIViewController?,
                _ options: [NativeAdClient.AnyAdLoaderOption]?, _ count: Int, _ keywords: [String]
            ) async throws -> [NativeAd]
    }

    // MARK: - Backward-compatible overloads (no keywords)

    extension NativeAdClient {
        /// Convenience: loads a native ad with no contextual keywords.
        public func loadAd(
            _ adUnitID: String,
            _ rootViewController: UIViewController?,
            _ options: [NativeAdClient.AnyAdLoaderOption]?
        ) async throws -> NativeAd {
            try await loadAd(adUnitID, rootViewController, options, [])
        }

        /// Convenience: batch-loads native ads with no contextual keywords.
        public func loadAds(
            _ adUnitID: String,
            _ rootViewController: UIViewController?,
            _ options: [NativeAdClient.AnyAdLoaderOption]?,
            _ count: Int
        ) async throws -> [NativeAd] {
            try await loadAds(adUnitID, rootViewController, options, count, [])
        }
    }
#endif
