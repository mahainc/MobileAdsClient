//
//  BackgroundFillApplier.swift
//  MobileAdsClient
//
//  Applies `NativeAdClient.Configuration.BackgroundFill` to any UIView.
//  Solid fills set `backgroundColor`; gradient fills insert a managed
//  `CAGradientLayer` below other sublayers and reuse it across re-styles
//  via an associated object (avoids subclassing — the outer ad views all
//  inherit from Google's `NativeAdView`).
//

#if canImport(UIKit)
import NativeAdClient
import ObjectiveC
import UIKit

@MainActor private var NativeAdGradientLayerKey: UInt8 = 0

extension UIView {

	public func applyBackgroundFill(_ fill: NativeAdClient.Configuration.BackgroundFill) {
		switch fill.mode {
		case .solid(let color):
			backgroundColor = color
			existingNativeAdGradientLayer?.removeFromSuperlayer()
			existingNativeAdGradientLayer = nil

		case .gradient(let gradient):
			backgroundColor = .clear

			let gradientLayer: CAGradientLayer
			if let existing = existingNativeAdGradientLayer {
				gradientLayer = existing
			} else {
				gradientLayer = CAGradientLayer()
				layer.insertSublayer(gradientLayer, at: 0)
				existingNativeAdGradientLayer = gradientLayer
			}

			CATransaction.begin()
			CATransaction.setDisableActions(true)
			gradientLayer.colors = gradient.colors.map(\.cgColor)
			gradientLayer.locations = gradient.locations
			let (start, end) = gradient.direction.points
			gradientLayer.startPoint = start
			gradientLayer.endPoint = end
			gradientLayer.frame = bounds
			CATransaction.commit()
		}
	}

	public func layoutNativeAdGradient() {
		guard let gradientLayer = existingNativeAdGradientLayer else { return }
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		gradientLayer.frame = bounds
		CATransaction.commit()
	}

	private var existingNativeAdGradientLayer: CAGradientLayer? {
		get { objc_getAssociatedObject(self, &NativeAdGradientLayerKey) as? CAGradientLayer }
		set { objc_setAssociatedObject(self, &NativeAdGradientLayerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}
}

extension NativeAdClient.Configuration.Gradient.Direction {
	fileprivate var points: (start: CGPoint, end: CGPoint) {
		switch self {
		case .vertical:           return (CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.5, y: 1.0))
		case .horizontal:         return (CGPoint(x: 0.0, y: 0.5), CGPoint(x: 1.0, y: 0.5))
		case .diagonalDown:       return (CGPoint(x: 0.0, y: 0.0), CGPoint(x: 1.0, y: 1.0))
		case .diagonalUp:         return (CGPoint(x: 0.0, y: 1.0), CGPoint(x: 1.0, y: 0.0))
		case let .custom(s, e):   return (s, e)
		}
	}
}
#endif
