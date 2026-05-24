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
	private var pendingBatchRequests: [UUID: BatchAdRequestContext] = [:]
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
			let loaderOptions: [GADAdLoaderOptions] = options?.map { $0.unwrapped.toGADAdLoaderOptions() } ?? []

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

			// GMA requires GADAdLoader methods on the main thread. We hop here
			// so the SDK's internal WebKit/UIKit prep runs in the right
			// context; register the pending request through `queue` before
			// arming the timeout so the timeout block can never observe an
			// empty `pendingRequests` for this id.
			DispatchQueue.main.async { [weak self] in
				guard let self = self else {
					continuation.resume(throwing: CancellationError())
					return
				}

				let adLoader = AdLoader(
					adUnitID: adUnitID,
					rootViewController: viewController,
					adTypes: [.native],
					options: loaderOptions
				)
				adLoader.delegate = self

				let context = AdRequestContext(
					id: requestID,
					adUnitID: adUnitID,
					adLoader: adLoader,
					continuation: continuation,
					timeoutTask: timeoutTask
				)

				self.queue.async(flags: .barrier) {
					self.pendingRequests[requestID] = context
				}

				DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)

				adLoader.load(request)
			}
		}
	}

	/// Batch native-ad load. One `AdLoader.load(request)` paired with a
	/// `MultipleAdsAdLoaderOptions(numberOfAds: count)` returns up to `count`
	/// ads via repeated `didReceive` delegate callbacks. Resumes the
	/// continuation once `count` ads have landed, or with whatever has been
	/// accumulated so far if `didFailToReceive` fires or the timeout elapses.
	/// Empty arrays are valid — the caller (typically a pool refill) just
	/// schedules another attempt later.
	public func loadAds(
		adUnitID: String,
		from viewController: UIViewController?,
		options: [NativeAdClient.AnyAdLoaderOption]?,
		count: Int,
		timeout: TimeInterval = 15
	) async throws -> [NativeAd] {
		guard count > 0 else { return [] }
		#if DEBUG
		print("📤 NativeAdManager loadAds START unit=\(adUnitID) count=\(count)")
		#endif
		return try await withCheckedThrowingContinuation { continuation in
			let requestID = UUID()
			let request = Request()
			var loaderOptions: [GADAdLoaderOptions] = options?.map { $0.unwrapped.toGADAdLoaderOptions() } ?? []
			let multiple = MultipleAdsAdLoaderOptions()
			multiple.numberOfAds = count
			loaderOptions.append(multiple)

			let timeoutTask = DispatchWorkItem { [weak self] in
				guard let self = self else { return }
				self.queue.async(flags: .barrier) {
					guard let context = self.pendingBatchRequests.removeValue(forKey: requestID) else { return }
					context.continuation.resume(returning: context.buffer)
				}
			}

			DispatchQueue.main.async { [weak self] in
				guard let self = self else {
					continuation.resume(throwing: CancellationError())
					return
				}

				let adLoader = AdLoader(
					adUnitID: adUnitID,
					rootViewController: viewController,
					adTypes: [.native],
					options: loaderOptions
				)
				adLoader.delegate = self

				let context = BatchAdRequestContext(
					id: requestID,
					adUnitID: adUnitID,
					adLoader: adLoader,
					expectedCount: count,
					continuation: continuation,
					timeoutTask: timeoutTask
				)

				self.queue.async(flags: .barrier) {
					self.pendingBatchRequests[requestID] = context
				}

				DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)

				adLoader.load(request)
			}
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

	/// Append a freshly-received ad to a batch context's buffer. When the
	/// buffer reaches `expectedCount` the continuation is resumed and the
	/// context is removed. Earlier delegate firings just accumulate.
	private func appendBatch(requestID: UUID, ad: NativeAd) {
		queue.async(flags: .barrier) {
			guard let context = self.pendingBatchRequests[requestID] else { return }
			context.buffer.append(ad)
			if context.buffer.count >= context.expectedCount {
				context.timeoutTask.cancel()
				let result = context.buffer
				self.pendingBatchRequests.removeValue(forKey: requestID)
				context.continuation.resume(returning: result)
			}
		}
	}

	/// Resolve a batch context early (e.g., on `didFailToReceive`) by handing
	/// back whatever has accumulated so far. Empty results are valid.
	private func completeBatch(requestID: UUID) {
		queue.async(flags: .barrier) {
			guard let context = self.pendingBatchRequests.removeValue(forKey: requestID) else { return }
			context.timeoutTask.cancel()
			context.continuation.resume(returning: context.buffer)
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
			if let (id, _) = self.pendingRequests.first(where: { $0.value.adLoader === adLoader }) {
				self.complete(requestID: id, result: .success(nativeAd))
			} else if let (id, _) = self.pendingBatchRequests.first(where: { $0.value.adLoader === adLoader }) {
				self.appendBatch(requestID: id, ad: nativeAd)
			}
		}
	}

	public func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
		#if DEBUG
		print("⛔️ NativeAdManager didFailToReceive unit=\(adLoader.adUnitID) error=\(error.localizedDescription)")
		#endif
		queue.async {
			if let (id, _) = self.pendingRequests.first(where: { $0.value.adLoader === adLoader }) {
				self.complete(requestID: id, result: .failure(error))
			} else if let (id, _) = self.pendingBatchRequests.first(where: { $0.value.adLoader === adLoader }) {
				self.completeBatch(requestID: id)
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

/// Companion to `AdRequestContext` for batch loads. Holds a growing buffer of
/// received ads and the `expectedCount` that triggers completion. Mutated only
/// under the manager's `queue` barrier.
private final class BatchAdRequestContext: @unchecked Sendable {
	let id: UUID
	let adUnitID: String
	let adLoader: AdLoader
	let expectedCount: Int
	let continuation: CheckedContinuation<[NativeAd], Error>
	let timeoutTask: DispatchWorkItem
	var buffer: [NativeAd] = []

	init(
		id: UUID,
		adUnitID: String,
		adLoader: AdLoader,
		expectedCount: Int,
		continuation: CheckedContinuation<[NativeAd], Error>,
		timeoutTask: DispatchWorkItem
	) {
		self.id = id
		self.adUnitID = adUnitID
		self.adLoader = adLoader
		self.expectedCount = expectedCount
		self.continuation = continuation
		self.timeoutTask = timeoutTask
	}
}
#endif
