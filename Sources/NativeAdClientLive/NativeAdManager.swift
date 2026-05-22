//
//  NativeAdManager.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 13/2/25.
//

#if canImport(UIKit)
@preconcurrency import AdRevenueClient
import ComposableArchitecture
@preconcurrency import GoogleMobileAds
import NativeAdClient
import UIKit

final internal class NativeAdManager: NSObject, @unchecked Sendable {
	
	private let queue = DispatchQueue(label: "com.app.NativeAdManager.\(UUID().uuidString)", attributes: .concurrent)
	
	private var nativeAds: [String: [NativeAd]] = [:]
	private var pendingRequests: [UUID: AdRequestContext] = [:]
}

// MARK: - Public

extension NativeAdManager {
	
	public func loadAd(
		adUnitID: String,
		from viewController: UIViewController?,
		options: [NativeAdClient.AnyAdLoaderOption]?,
		timeout: TimeInterval = 10
	) async throws -> NativeAd {
		#if DEBUG
		print("📤 NativeAdManager loadAd START unit=\(adUnitID)")
		#endif
		return try await withCheckedThrowingContinuation { continuation in
			let requestID = UUID()
			let request = Request()
			
			var loaderOptions: [GADAdLoaderOptions] = []
			if let options = options {
				loaderOptions = options.map { $0.unwrapped.toGADAdLoaderOptions() }
			}
			
			let adLoader = AdLoader(
				adUnitID: adUnitID,
				rootViewController: viewController,
				adTypes: [.native],
				options: loaderOptions
			)
			adLoader.delegate = self
			
			let timeoutTask = DispatchWorkItem { [weak self] in
				guard let self = self else { return }
				self.queue.async(flags: .barrier) {
					guard let context = self.pendingRequests.removeValue(forKey: requestID) else { return }
					context.continuation.resume(throwing: NSError(
						domain: "NativeAdManager",
						code: -1001,
						userInfo: [NSLocalizedDescriptionKey: "Timeout: NativeAd not loaded for \(adUnitID)"]
					))
				}
			}
			
			DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
			
			let context = AdRequestContext(
				id: requestID,
				adUnitID: adUnitID,
				adLoader: adLoader,
				continuation: continuation,
				timeoutTask: timeoutTask
			)
			
			queue.async(flags: .barrier) {
				self.pendingRequests[requestID] = context
			}
			
			adLoader.load(request)
		}
	}
}

// MARK: - Private Helpers

extension NativeAdManager {
	
	private func complete(requestID: UUID, result: Result<NativeAd, Error>) {
		queue.async(flags: .barrier) {
			guard let context = self.pendingRequests.removeValue(forKey: requestID) else { return }
			context.timeoutTask.cancel()
			
			switch result {
			case .success(let ad):
				context.continuation.resume(returning: ad)
			case .failure(let error):
				context.continuation.resume(throwing: error)
			}
		}
	}
	
	private func getAd(for adUnitID: String) -> NativeAd? {
		var ad: NativeAd?
		queue.sync {
			if let ads = nativeAds[adUnitID], !ads.isEmpty {
				ad = ads.first
			}
		}
		return ad
	}
	
	private func removeAd(for adUnitID: String) {
		queue.async(flags: .barrier) {
			self.nativeAds.removeValue(forKey: adUnitID)
		}
	}
}

// MARK: - NativeAdLoaderDelegate

extension NativeAdManager: NativeAdLoaderDelegate {
	
	public func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
		#if DEBUG
		print("🖼️ RECEIVED NATIVE AD FOR ID: \(adLoader.adUnitID)")
		#endif
		let adUnitID = adLoader.adUnitID
		nativeAd.delegate = self

		// Publish every paid impression into `AdRevenueClient` so `AdRevenueSyncer`
		// fans out to Adjust + Analytics. Matches the pattern
		// `BaseAdManager.attachPaidEventHandler` uses for full-screen formats.
		nativeAd.paidEventHandler = { adValue in
			@Dependency(\.adRevenueClient) var adRevenueClient
			adRevenueClient.publish(AdRevenueEvent(
				amount: Double(truncating: adValue.value),
				currency: adValue.currencyCode,
				adUnitId: adUnitID,
				format: .native,
				source: .googleMobileAds,
				receivedAt: .now
			))
		}

		queue.async(flags: .barrier) {
			if self.nativeAds[adUnitID] != nil {
				self.nativeAds[adUnitID]?.append(nativeAd)
			} else {
				self.nativeAds[adUnitID] = [nativeAd]
			}
		}

		queue.async {
			let matchingRequest = self.pendingRequests.first { $0.value.adLoader === adLoader }
			if let (id, _) = matchingRequest {
				self.complete(requestID: id, result: .success(nativeAd))
			}
		}
	}
	
	public func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
		#if DEBUG
		print("⛔️ NativeAdManager didFailToReceive unit=\(adLoader.adUnitID) error=\(error.localizedDescription)")
		#endif
		queue.async {
			let matchingRequest = self.pendingRequests.first { $0.value.adLoader === adLoader }
			if let (id, _) = matchingRequest {
				self.complete(requestID: id, result: .failure(error))
			}
		}
	}
}

// MARK: - NativeAdDelegate

extension NativeAdManager: NativeAdDelegate {
	public func nativeAdDidRecordClick(_ nativeAd: NativeAd) {}
	public func nativeAdDidRecordImpression(_ nativeAd: NativeAd) {}
	public func nativeAdWillPresentScreen(_ nativeAd: NativeAd) {}
	public func nativeAdWillDismissScreen(_ nativeAd: NativeAd) {}
	public func nativeAdDidDismissScreen(_ nativeAd: NativeAd) {}
}

// MARK: - Request Context

private final class AdRequestContext: @unchecked Sendable {
	let id: UUID
	let adUnitID: String
	let adLoader: AdLoader
	let continuation: CheckedContinuation<NativeAd, Error>
	let timeoutTask: DispatchWorkItem

	init(
		id: UUID,
		adUnitID: String,
		adLoader: AdLoader,
		continuation: CheckedContinuation<NativeAd, Error>,
		timeoutTask: DispatchWorkItem
	) {
		self.id = id
		self.adUnitID = adUnitID
		self.adLoader = adLoader
		self.continuation = continuation
		self.timeoutTask = timeoutTask
	}
}
#endif
