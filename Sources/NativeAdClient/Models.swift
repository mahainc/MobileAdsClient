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

// MARK: - Configuration

extension NativeAdClient {
	public enum Configuration {
		public protocol Kind: Sendable, Equatable { }

		// MARK: - Shared building blocks

		public struct Style: Sendable, Equatable {
			public struct ButtonShape: Sendable, Equatable, Hashable {
				public enum Mode: Sendable, Equatable, Hashable {
					case rect(cornerRadius: CGFloat)
					case capsule
				}

				public var mode: Mode

				public init(mode: Mode) {
					self.mode = mode
				}

				public static func rect(cornerRadius: CGFloat) -> ButtonShape {
					ButtonShape(mode: .rect(cornerRadius: cornerRadius))
				}

				public static let capsule = ButtonShape(mode: .capsule)
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

			public static let compact: Style = .init()

			public static let fullScreen: Style = .init(
				backgroundColor: .systemBackground,
				buttonShape: .capsule
			)

			public static let advanced: Style = .init(
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

			public static let custom: Style = .init(
				backgroundColor: .clear,
				containerBackgroundColor: UIColor(red: 122 / 255, green: 159 / 255, blue: 126 / 255, alpha: 1),
				headlineTextColor: UIColor(red: 66 / 255, green: 66 / 255, blue: 66 / 255, alpha: 1),
				buttonShape: .rect(cornerRadius: 5)
			)

			public static let row: Style = .init(
				backgroundColor: .secondarySystemBackground,
				actionButtonBackgroundColor: .systemBlue,
				actionButtonTitleColor: .white,
				buttonShape: .capsule,
				attributionBackgroundColor: .systemGray5,
				attributionTextColor: .secondaryLabel
			)
		}

		public struct BodyDisplay: Sendable, Equatable, Hashable {
			public enum Mode: Sendable, Equatable, Hashable {
				case hidden
				case full
				case truncated(lines: Int)
			}

			public var mode: Mode

			public init(mode: Mode = .full) {
				self.mode = mode
			}

			public static let hidden = BodyDisplay(mode: .hidden)
			public static let full = BodyDisplay(mode: .full)
			public static func truncated(lines: Int) -> BodyDisplay {
				BodyDisplay(mode: .truncated(lines: lines))
			}
		}

		public struct Metrics: Sendable, Equatable, Hashable {
			public var iconSize: CGSize
			public var iconCornerRadius: CGFloat
			public var ctaMinHeight: CGFloat
			public var horizontalSpacing: CGFloat
			public var verticalSpacing: CGFloat

			public init(
				iconSize: CGSize = CGSize(width: 56, height: 56),
				iconCornerRadius: CGFloat = 10,
				ctaMinHeight: CGFloat = 36,
				horizontalSpacing: CGFloat = 12,
				verticalSpacing: CGFloat = 4
			) {
				self.iconSize = iconSize
				self.iconCornerRadius = iconCornerRadius
				self.ctaMinHeight = ctaMinHeight
				self.horizontalSpacing = horizontalSpacing
				self.verticalSpacing = verticalSpacing
			}

			public static let `default` = Metrics()
			public static let row = Metrics()
			public static let rowStacked = Metrics(
				iconSize: CGSize(width: 64, height: 64),
				ctaMinHeight: 44
			)
			public static let compact = Metrics(
				iconSize: CGSize(width: 36, height: 36),
				iconCornerRadius: 8,
				ctaMinHeight: 40,
				horizontalSpacing: 12,
				verticalSpacing: 8
			)
			public static let custom = Metrics(
				iconSize: CGSize(width: 80, height: 80),
				iconCornerRadius: 5,
				ctaMinHeight: 44,
				horizontalSpacing: 12,
				verticalSpacing: 8
			)
			public static let fullScreen = Metrics(
				iconSize: CGSize(width: 56, height: 56),
				iconCornerRadius: 12,
				ctaMinHeight: 56,
				horizontalSpacing: 12,
				verticalSpacing: 2
			)
			public static let advanced = Metrics(
				iconSize: CGSize(width: 50, height: 50),
				iconCornerRadius: 5,
				ctaMinHeight: 40,
				horizontalSpacing: 8,
				verticalSpacing: 8
			)
		}

		// MARK: - Per-template configurations

		public struct Row: Kind, Hashable {
			public struct Layout: Sendable, Equatable, Hashable {
				public enum Mode: Sendable, Equatable, Hashable {
					case inline
					case stacked
				}

				public var mode: Mode

				public init(mode: Mode = .inline) {
					self.mode = mode
				}

				public static let inline = Layout(mode: .inline)
				public static let stacked = Layout(mode: .stacked)
			}

			public var style: Style
			public var bodyDisplay: BodyDisplay
			public var layout: Layout
			public var insets: UIEdgeInsets
			public var metrics: Metrics

			public init(
				style: Style = .row,
				bodyDisplay: BodyDisplay = .full,
				layout: Layout = .inline,
				insets: UIEdgeInsets = .init(top: 12, left: 14, bottom: 12, right: 14),
				metrics: Metrics? = nil
			) {
				self.style = style
				self.bodyDisplay = bodyDisplay
				self.layout = layout
				self.insets = insets
				// nil → layout-matched default so existing call sites that pass `.stacked`
				// without an explicit `metrics:` still get the bigger icon / taller CTA.
				self.metrics = metrics ?? (layout.mode == .stacked ? .rowStacked : .row)
			}

			public static let `default` = Row()
			public static let inline = Row(layout: .inline)
			public static let stacked = Row(layout: .stacked)

			public func hash(into hasher: inout Hasher) {
				hasher.combine(bodyDisplay)
				hasher.combine(layout)
				hasher.combine(insets.top)
				hasher.combine(insets.left)
				hasher.combine(insets.bottom)
				hasher.combine(insets.right)
				hasher.combine(metrics)
			}
		}

		public struct Compact: Kind, Hashable {
			public var style: Style
			public var bodyDisplay: BodyDisplay
			public var metrics: Metrics

			public init(
				style: Style = .compact,
				bodyDisplay: BodyDisplay = .full,
				metrics: Metrics = .compact
			) {
				self.style = style
				self.bodyDisplay = bodyDisplay
				self.metrics = metrics
			}

			public static let `default` = Compact()

			public func hash(into hasher: inout Hasher) {
				hasher.combine(bodyDisplay)
				hasher.combine(metrics)
			}
		}

		public struct Custom: Kind, Hashable {
			public var style: Style
			public var bodyDisplay: BodyDisplay
			public var metrics: Metrics

			public init(
				style: Style = .custom,
				bodyDisplay: BodyDisplay = .full,
				metrics: Metrics = .custom
			) {
				self.style = style
				self.bodyDisplay = bodyDisplay
				self.metrics = metrics
			}

			public static let `default` = Custom()

			public func hash(into hasher: inout Hasher) {
				hasher.combine(bodyDisplay)
				hasher.combine(metrics)
			}
		}
	}

	// MARK: - Type-erased wrapper

	public struct AnyConfiguration: Sendable, Equatable {
		public let base: any Configuration.Kind
		private let equals: @Sendable (any Configuration.Kind) -> Bool

		public init<C: Configuration.Kind>(_ base: C) {
			self.base = base
			self.equals = { ($0 as? C) == base }
		}

		public static func == (lhs: AnyConfiguration, rhs: AnyConfiguration) -> Bool {
			lhs.equals(rhs.base)
		}
	}
}
#endif
