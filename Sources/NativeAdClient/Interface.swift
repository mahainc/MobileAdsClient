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
                _ options: [NativeAdClient.AnyAdLoaderOption]?, _ keywords: [String],
                _ featureID: String, _ slotRef: String
            ) async throws -> NativeAd
        /// Batch fetch up to `count` native ads in a single auction via
        /// `MultipleAdsAdLoaderOptions`. Returns whatever ads landed before the
        /// SDK reported completion / failure / timeout — empty array is valid.
        public var loadAds:
            @Sendable (
                _ adUnitID: String, _ rootViewController: UIViewController?,
                _ options: [NativeAdClient.AnyAdLoaderOption]?, _ count: Int, _ keywords: [String],
                _ featureID: String, _ slotRef: String
            ) async throws -> [NativeAd]
    }

    // MARK: - Backward-compatible overloads (no keywords / no featureID)

    extension NativeAdClient {
        /// Convenience: loads a native ad with no contextual keywords.
        public func loadAd(
            _ adUnitID: String,
            _ rootViewController: UIViewController?,
            _ options: [NativeAdClient.AnyAdLoaderOption]?,
            _ keywords: [String] = [],
            featureID: String = "",
            slotRef: String = ""
        ) async throws -> NativeAd {
            try await loadAd(adUnitID, rootViewController, options, keywords, featureID, slotRef)
        }

        /// Convenience: batch-loads native ads with no contextual keywords.
        public func loadAds(
            _ adUnitID: String,
            _ rootViewController: UIViewController?,
            _ options: [NativeAdClient.AnyAdLoaderOption]?,
            _ count: Int,
            _ keywords: [String] = [],
            featureID: String = "",
            slotRef: String = ""
        ) async throws -> [NativeAd] {
            try await loadAds(adUnitID, rootViewController, options, count, keywords, featureID, slotRef)
        }
    }
#endif
