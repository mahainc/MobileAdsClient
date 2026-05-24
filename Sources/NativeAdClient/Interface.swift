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
	public var loadAd: @Sendable (_ adUnitID: String, _ rootViewController: UIViewController?, _ options: [NativeAdClient.AnyAdLoaderOption]?) async throws -> NativeAd
	/// Batch fetch up to `count` native ads in a single auction via
	/// `MultipleAdsAdLoaderOptions`. Returns whatever ads landed before the
	/// SDK reported completion / failure / timeout — empty array is valid.
	public var loadAds: @Sendable (_ adUnitID: String, _ rootViewController: UIViewController?, _ options: [NativeAdClient.AnyAdLoaderOption]?, _ count: Int) async throws -> [NativeAd]
}
#endif
