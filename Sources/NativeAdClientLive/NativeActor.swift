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

    public init() { }
}

// MARK: - Public Methods

extension NativeActor {
    
	public func loadAd(
		adUnitID: String,
		from viewController: UIViewController?,
		options: [NativeAdClient.AnyAdLoaderOption]?
	) async throws -> NativeAd {
        return try await manager.loadAd(
			adUnitID: adUnitID,
			from: viewController,
			options: options
		)
    }
}
#endif
