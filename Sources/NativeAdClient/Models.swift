//
//  Models.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 9/6/25.
//

import Foundation
#if canImport(UIKit)
import GoogleMobileAds
import UIKit

// MARK: - AdChoicesOptions

extension NativeAdClient {

	public protocol AdLoaderOption: Sendable, Equatable {
		func toGADAdLoaderOptions() -> GADAdLoaderOptions
	}
}

extension NativeAdClient {
	
	public struct AnyAdLoaderOption: Sendable, Equatable {
		private let base: any AdLoaderOption
		private let equals: @Sendable (any AdLoaderOption) -> Bool
		
		public init<T: AdLoaderOption & Equatable>(_ base: T) {
			self.base = base
			self.equals = { ($0 as? T) == base }
		}
		
		public var unwrapped: any AdLoaderOption {
			return base
		}
		
		public static func == (lhs: AnyAdLoaderOption, rhs: AnyAdLoaderOption) -> Bool {
			return lhs.equals(rhs.base)
		}
	}
}

extension NativeAdClient {
	
	public struct AdChoicesPositionOption: AdLoaderOption {
		private let corner: AdChoicesCorner
		
		public init(corner: AdChoicesCorner) {
			self.corner = corner
		}
		
		public enum AdChoicesCorner: Int, Sendable, Equatable {
			case topLeft
			case topRight
			case bottomRight
			case bottomLeft
		}
		
		public func toGADAdLoaderOptions() -> GADAdLoaderOptions {
			let adChoicesPosition: AdChoicesPosition
			switch corner {
			case .topLeft:
				adChoicesPosition = .topLeftCorner
			case .topRight:
				adChoicesPosition = .topRightCorner
			case .bottomRight:
				adChoicesPosition = .bottomRightCorner
			case .bottomLeft:
				adChoicesPosition = .bottomLeftCorner
			}
			
			let nativeOptions = NativeAdViewAdOptions()
			nativeOptions.preferredAdChoicesPosition = adChoicesPosition
			
			return nativeOptions
		}
	}
}

extension NativeAdClient {
	
	public struct MediaAspectRatioOption: AdLoaderOption {
		
		private let type: MediaAspectRatioType
		
		public init(type: MediaAspectRatioType) {
			self.type = type
		}
		
		public enum MediaAspectRatioType: Int, Sendable, Equatable {
			case unknown
			case any
			case landscape
			case portrait
			case square
			
			public func toMediaAspectRatio() -> MediaAspectRatio {
				switch self {
				case .unknown:
					return .unknown
				case .any:
					return .unknown
				case .landscape:
					return .landscape
				case .portrait:
					return .portrait
				case .square:
					return .square
				}
			}
		}
		
		public func toGADAdLoaderOptions() -> GADAdLoaderOptions {
			let mediaOptions = NativeAdMediaAdLoaderOptions()
			mediaOptions.mediaAspectRatio = type.toMediaAspectRatio()
			return mediaOptions
		}
	}
}

extension NativeAdClient {
	
	public struct VideoPlaybackOption: AdLoaderOption {
		private let shouldStartMuted: Bool
		private let areCustomControlsRequested: Bool
		private let isClickToExpandRequested: Bool
		
		public init(
			shouldStartMuted: Bool = false,
			areCustomControlsRequested: Bool = false,
			isClickToExpandRequested: Bool = false
		) {
			self.shouldStartMuted = shouldStartMuted
			self.areCustomControlsRequested = areCustomControlsRequested
			self.isClickToExpandRequested = isClickToExpandRequested
		}
		
		public func toGADAdLoaderOptions() -> GADAdLoaderOptions {
			let videoOptions = VideoOptions()
			videoOptions.shouldStartMuted = shouldStartMuted
			videoOptions.areCustomControlsRequested = areCustomControlsRequested
			videoOptions.isClickToExpandRequested = isClickToExpandRequested
			
			return videoOptions
		}
	}
}

extension NativeAd: @retroactive @unchecked Sendable {

}

// MARK: - AdStyle

extension NativeAdClient {

	public struct AdStyle: Sendable, Equatable {

		public enum CTAShape: Sendable, Equatable {
			case rect(cornerRadius: CGFloat)
			case capsule
		}

		public var backgroundColor: UIColor
		public var actionButtonBackgroundColor: UIColor
		public var actionButtonTitleColor: UIColor
		public var ctaShape: CTAShape
		public var attributionBackgroundColor: UIColor
		public var attributionTextColor: UIColor
		public var storeBackgroundColor: UIColor
		public var storeTextColor: UIColor
		public var priceBackgroundColor: UIColor
		public var priceTextColor: UIColor

		public init(
			backgroundColor: UIColor = .secondarySystemBackground,
			actionButtonBackgroundColor: UIColor = .systemBlue,
			actionButtonTitleColor: UIColor = .white,
			ctaShape: CTAShape = .rect(cornerRadius: 8),
			attributionBackgroundColor: UIColor = .systemBlue,
			attributionTextColor: UIColor = .white,
			storeBackgroundColor: UIColor = .systemGreen,
			storeTextColor: UIColor = .white,
			priceBackgroundColor: UIColor = .systemGreen,
			priceTextColor: UIColor = .white
		) {
			self.backgroundColor = backgroundColor
			self.actionButtonBackgroundColor = actionButtonBackgroundColor
			self.actionButtonTitleColor = actionButtonTitleColor
			self.ctaShape = ctaShape
			self.attributionBackgroundColor = attributionBackgroundColor
			self.attributionTextColor = attributionTextColor
			self.storeBackgroundColor = storeBackgroundColor
			self.storeTextColor = storeTextColor
			self.priceBackgroundColor = priceBackgroundColor
			self.priceTextColor = priceTextColor
		}

		/// Preset matching `CompactNativeAdView`'s historical defaults.
		public static let compact: AdStyle = .init()
	}
}
#endif
