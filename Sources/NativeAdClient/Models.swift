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
		private let corner: Corner

		public init(corner: Corner) {
			self.corner = corner
		}

		public enum Corner: Int, Sendable, Equatable {
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
		private let ratio: Ratio

		public init(ratio: Ratio) {
			self.ratio = ratio
		}

		public enum Ratio: Int, Sendable, Equatable {
			case unknown
			case any
			case landscape
			case portrait
			case square

			func toMediaAspectRatio() -> MediaAspectRatio {
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
			mediaOptions.mediaAspectRatio = ratio.toMediaAspectRatio()
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
		public enum ButtonShape: Sendable, Equatable {
			case rect(cornerRadius: CGFloat)
			case capsule
		}

		public var backgroundColor: UIColor
		public var containerBackgroundColor: UIColor
		public var headlineTextColor: UIColor
		public var bodyTextColor: UIColor
		public var sponsorTextColor: UIColor
		public var actionButtonBackgroundColor: UIColor
		public var actionButtonTitleColor: UIColor
		public var buttonShape: ButtonShape
		public var attributionBackgroundColor: UIColor
		public var attributionTextColor: UIColor
		public var storeBackgroundColor: UIColor
		public var storeTextColor: UIColor
		public var priceBackgroundColor: UIColor
		public var priceTextColor: UIColor
		public var closeButtonTintColor: UIColor
		public var closeButtonBackgroundColor: UIColor

		public init(
			backgroundColor: UIColor = .secondarySystemBackground,
			containerBackgroundColor: UIColor = .clear,
			headlineTextColor: UIColor = .label,
			bodyTextColor: UIColor = .secondaryLabel,
			sponsorTextColor: UIColor = .secondaryLabel,
			actionButtonBackgroundColor: UIColor = .systemBlue,
			actionButtonTitleColor: UIColor = .white,
			buttonShape: ButtonShape = .rect(cornerRadius: 8),
			attributionBackgroundColor: UIColor = .systemBlue,
			attributionTextColor: UIColor = .white,
			storeBackgroundColor: UIColor = .systemGreen,
			storeTextColor: UIColor = .white,
			priceBackgroundColor: UIColor = .systemGreen,
			priceTextColor: UIColor = .white,
			closeButtonTintColor: UIColor = .label,
			closeButtonBackgroundColor: UIColor = UIColor.label.withAlphaComponent(0.08)
		) {
			self.backgroundColor = backgroundColor
			self.containerBackgroundColor = containerBackgroundColor
			self.headlineTextColor = headlineTextColor
			self.bodyTextColor = bodyTextColor
			self.sponsorTextColor = sponsorTextColor
			self.actionButtonBackgroundColor = actionButtonBackgroundColor
			self.actionButtonTitleColor = actionButtonTitleColor
			self.buttonShape = buttonShape
			self.attributionBackgroundColor = attributionBackgroundColor
			self.attributionTextColor = attributionTextColor
			self.storeBackgroundColor = storeBackgroundColor
			self.storeTextColor = storeTextColor
			self.priceBackgroundColor = priceBackgroundColor
			self.priceTextColor = priceTextColor
			self.closeButtonTintColor = closeButtonTintColor
			self.closeButtonBackgroundColor = closeButtonBackgroundColor
		}

		/// Preset matching `CompactNativeAdView`'s historical defaults.
		public static let compact: AdStyle = .init()

		/// Preset matching `FullScreenNativeAdView`'s historical defaults — capsule CTA, system-background canvas.
		public static let fullScreen: AdStyle = .init(
			backgroundColor: .systemBackground,
			buttonShape: .capsule
		)

		/// Preset matching `NativeAdvancedView`'s historical look — light-blue container, outlined attribution chip, soft-tinted CTA + store/price chips.
		public static let advanced: AdStyle = .init(
			backgroundColor: .clear,
			containerBackgroundColor: UIColor(red: 234 / 255, green: 240 / 255, blue: 253 / 255, alpha: 1),
			headlineTextColor: UIColor(red: 66 / 255, green: 66 / 255, blue: 66 / 255, alpha: 1),
			actionButtonBackgroundColor: .systemBlue.withAlphaComponent(0.15),
			actionButtonTitleColor: .systemBlue,
			buttonShape: .rect(cornerRadius: 5),
			attributionBackgroundColor: .clear,
			attributionTextColor: .systemBlue,
			storeBackgroundColor: .systemGreen.withAlphaComponent(0.15),
			storeTextColor: .systemGreen,
			priceBackgroundColor: .systemGreen.withAlphaComponent(0.15),
			priceTextColor: .systemGreen
		)

		/// Preset matching `CustomNativeAdView`'s historical look — green container, solid attribution chip, solid CTA.
		public static let custom: AdStyle = .init(
			backgroundColor: .clear,
			containerBackgroundColor: UIColor(red: 122 / 255, green: 159 / 255, blue: 126 / 255, alpha: 1),
			headlineTextColor: UIColor(red: 66 / 255, green: 66 / 255, blue: 66 / 255, alpha: 1),
			buttonShape: .rect(cornerRadius: 5)
		)

		/// Preset for `RowNativeAdView` — secondary canvas, capsule CTA, and a subtle gray "Sponsored" chip that reads as an ad without shouting.
		public static let row: AdStyle = .init(
			backgroundColor: .secondarySystemBackground,
			actionButtonBackgroundColor: .systemBlue,
			actionButtonTitleColor: .white,
			buttonShape: .capsule,
			attributionBackgroundColor: .systemGray5,
			attributionTextColor: .secondaryLabel
		)
	}
}
#endif
