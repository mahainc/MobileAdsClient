//
//  SkeletonShimmer.swift
//  MobileAdsClient
//
//  Static placeholder for native-ad slots whose creatives haven't been bound
//  yet. Used by `RowMediaNativeView` when `store.nativeAd == nil`.
//
//  Deliberately not animated — earlier `TimelineView(.animation)` revisions
//  re-evaluated the body at the display refresh rate (~60fps) per visible
//  skeleton row, which dropped frames during scroll. A flat 3-stop gradient
//  is enough affordance for "loading ad" without per-frame cost.
//

#if canImport(UIKit)
import SwiftUI

public struct SkeletonShimmer: View {

    private let cornerRadius: CGFloat
    private let baseColor: Color
    private let highlightColor: Color

    public init(
        cornerRadius: CGFloat = 12,
        baseColor: Color = Color(white: 0.92),
        highlightColor: Color = Color(white: 0.96)
    ) {
        self.cornerRadius = cornerRadius
        self.baseColor = baseColor
        self.highlightColor = highlightColor
    }

    public var body: some View {
        #if DEBUG
        let _ = { print("⚪ SK body eval") }()
        #endif
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [baseColor, highlightColor, baseColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}
#endif
