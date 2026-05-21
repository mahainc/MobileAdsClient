//
//  UIFont+Extensions.swift
//  MobileAdsClient
//

#if canImport(UIKit)
import NativeAdClient
import UIKit

extension UIFont {
	func withWeight(_ weight: UIFont.Weight) -> UIFont {
		let descriptor = fontDescriptor.addingAttributes([
			.traits: [UIFontDescriptor.TraitKey.weight: weight]
		])
		return UIFont(descriptor: descriptor, size: pointSize)
	}
}

extension NativeAdClient.Configuration.AdFont {
	public var resolved: UIFont {
		switch mode {
		case let .textStyle(style, weight):
			let base = UIFont.preferredFont(forTextStyle: style)
			return weight.map { base.withWeight($0) } ?? base

		case let .system(size, weight, scaledFor):
			let base = UIFont.systemFont(ofSize: size, weight: weight)
			return scaledFor.map { UIFontMetrics(forTextStyle: $0).scaledFont(for: base) } ?? base

		case let .custom(name, size, scaledFor):
			let base = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
			return scaledFor.map { UIFontMetrics(forTextStyle: $0).scaledFont(for: base) } ?? base

		case let .fixed(font):
			return font
		}
	}
}
#endif
