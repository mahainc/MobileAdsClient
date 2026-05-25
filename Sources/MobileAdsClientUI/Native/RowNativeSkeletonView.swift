//
//  RowNativeSkeletonView.swift
//  MobileAdsClient
//
//  SwiftUI redacted skeletons that mirror `RowNativeAdView` and
//  `RowMediaNativeAdView`. Rendered by `RowNativeView` /
//  `RowMediaNativeView` while `Native.State.nativeAd` is nil so an
//  unfilled slot reserves the shape of the future creative instead of
//  collapsing to a blank strip.
//

#if canImport(UIKit)
import NativeAdClient
import SwiftUI
import UIKit

// MARK: - Row variant (no media)

struct RowNativeSkeletonView: View {
    let configuration: NativeAdClient.Configuration.Row

    var body: some View {
        RowNativeSkeletonChrome(
            style: configuration.style,
            metrics: configuration.metrics,
            bodyDisplay: configuration.bodyDisplay,
            layoutMode: configuration.layout.mode
        )
        .padding(EdgeInsets(
            top: configuration.insets.top,
            leading: configuration.insets.left,
            bottom: configuration.insets.bottom,
            trailing: configuration.insets.right
        ))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(_RowSkeletonHelpers.background(configuration.style))
        .clipShape(
            RoundedRectangle(
                cornerRadius: configuration.metrics.containerCornerRadius,
                style: .continuous
            )
        )
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - Row + Media variant

struct RowMediaNativeSkeletonView: View {
    /// Fixed gap between the media block and the row chrome — mirrors
    /// `RowMediaNativeAdView.mediaToRowSpacing`.
    private let mediaToRowSpacing: CGFloat = 10
    let configuration: NativeAdClient.Configuration.RowMedia

    var body: some View {
        VStack(spacing: mediaToRowSpacing) {
            RoundedRectangle(
                cornerRadius: configuration.metrics.iconCornerRadius,
                style: .continuous
            )
            .fill(_RowSkeletonHelpers.placeholderTint)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)

            RowNativeSkeletonChrome(
                style: configuration.style,
                metrics: configuration.metrics,
                bodyDisplay: configuration.bodyDisplay,
                layoutMode: configuration.layout.mode
            )
        }
        .padding(EdgeInsets(
            top: configuration.insets.top,
            leading: configuration.insets.left,
            bottom: configuration.insets.bottom,
            trailing: configuration.insets.right
        ))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(_RowSkeletonHelpers.background(configuration.style))
        .clipShape(
            RoundedRectangle(
                cornerRadius: configuration.metrics.containerCornerRadius,
                style: .continuous
            )
        )
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared chrome

/// Inner icon + text-column (+ CTA, depending on layout) used by both row
/// skeleton variants. Pure layout — outer padding, background, clip, and
/// `.redacted` are applied by the caller so the chrome can be composed
/// underneath a media block without double-wrapping.
private struct RowNativeSkeletonChrome: View {
    let style: NativeAdClient.Configuration.Style
    let metrics: NativeAdClient.Configuration.Metrics
    let bodyDisplay: NativeAdClient.Configuration.BodyDisplay
    let layoutMode: NativeAdClient.Configuration.Row.Layout.Mode

    var body: some View {
        switch layoutMode {
        case .inline:
            HStack(alignment: .center, spacing: metrics.horizontalSpacing) {
                iconPlaceholder
                textColumn(includesCTA: false)
                ctaPlaceholder
            }
        case .stacked:
            HStack(alignment: .top, spacing: metrics.horizontalSpacing) {
                iconPlaceholder
                textColumn(includesCTA: true)
            }
        case .stackedFullCTA:
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: metrics.horizontalSpacing) {
                    iconPlaceholder
                    textColumn(includesCTA: false)
                }
                ctaPlaceholder
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: metrics.iconCornerRadius, style: .continuous)
            .fill(_RowSkeletonHelpers.placeholderTint)
            .frame(width: metrics.iconSize.width, height: metrics.iconSize.height)
    }

    @ViewBuilder
    private func textColumn(includesCTA: Bool) -> some View {
        VStack(alignment: .leading, spacing: metrics.verticalSpacing) {
            Text("Sponsored ad headline placeholder")
                .font(_RowSkeletonHelpers.font(for: style.text.headlineFont))
                .foregroundStyle(Color(uiColor: style.text.headline))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text("Advertiser name")
                    .font(_RowSkeletonHelpers.font(for: style.text.sponsorFont))
                    .foregroundStyle(Color(uiColor: style.text.sponsor))
                    .lineLimit(1)

                Text("Sponsored")
                    .font(_RowSkeletonHelpers.font(for: style.attribution.font))
                    .foregroundStyle(Color(uiColor: style.attribution.text))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color(uiColor: style.attribution.background),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            }

            switch bodyDisplay.mode {
            case .hidden:
                EmptyView()
            case .full:
                Text("Body text placeholder with two lines of supporting copy that wraps naturally to fill the column width.")
                    .font(_RowSkeletonHelpers.font(for: style.text.bodyFont))
                    .foregroundStyle(Color(uiColor: style.text.body))
                    .lineLimit(2)
            case .truncated(let lines):
                Text("Body text placeholder for truncated mode, sized to fit the configured line count.")
                    .font(_RowSkeletonHelpers.font(for: style.text.bodyFont))
                    .foregroundStyle(Color(uiColor: style.text.body))
                    .lineLimit(max(1, lines))
            }

            if includesCTA {
                ctaPlaceholder
                    .padding(.top, max(0, 10 - metrics.verticalSpacing))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var ctaPlaceholder: some View {
        Text("Install")
            .font(_RowSkeletonHelpers.font(for: style.actionButton.font))
            .foregroundStyle(Color(uiColor: style.actionButton.title))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(minHeight: metrics.ctaMinHeight)
            .background(Color(uiColor: style.actionButton.background), in: ctaShape)
    }

    private var ctaShape: AnyShape {
        switch style.actionButton.shape.mode {
        case .capsule:
            return AnyShape(Capsule(style: .continuous))
        case .rect(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

// MARK: - Shared helpers

private enum _RowSkeletonHelpers {
    static let placeholderTint = Color(uiColor: .label).opacity(0.18)

    // `.system(size:)` keeps the layout dimensions of the real font while
    // sidestepping the `UIFont -> Font` bridge — placeholder bars are sized
    // from the rendered text's metrics, so the point size is what matters.
    static func font(for adFont: NativeAdClient.Configuration.AdFont) -> Font {
        Font.system(size: adFont.resolved.pointSize)
    }

    @ViewBuilder
    static func background(_ style: NativeAdClient.Configuration.Style) -> some View {
        switch style.backgrounds.card.mode {
        case .solid(let uiColor):
            Color(uiColor: uiColor)
        case .gradient(let gradient):
            LinearGradient(
                stops: gradientStops(from: gradient),
                startPoint: gradient.direction.unitStart,
                endPoint: gradient.direction.unitEnd
            )
        }
    }

    private static func gradientStops(
        from gradient: NativeAdClient.Configuration.Gradient
    ) -> [Gradient.Stop] {
        let colors = gradient.colors.map(Color.init(uiColor:))
        if let locations = gradient.locations, locations.count == colors.count {
            return zip(colors, locations).map { color, location in
                Gradient.Stop(color: color, location: CGFloat(truncating: location))
            }
        }
        return colors.enumerated().map { idx, color in
            let location: CGFloat = colors.count <= 1 ? 0 : CGFloat(idx) / CGFloat(colors.count - 1)
            return Gradient.Stop(color: color, location: location)
        }
    }
}

private extension NativeAdClient.Configuration.Gradient.Direction {
    var unitStart: UnitPoint {
        switch self {
        case .vertical: return UnitPoint(x: 0.5, y: 0.0)
        case .horizontal: return UnitPoint(x: 0.0, y: 0.5)
        case .diagonalDown: return UnitPoint(x: 0.0, y: 0.0)
        case .diagonalUp: return UnitPoint(x: 0.0, y: 1.0)
        case .custom(let start, _): return UnitPoint(x: start.x, y: start.y)
        }
    }

    var unitEnd: UnitPoint {
        switch self {
        case .vertical: return UnitPoint(x: 0.5, y: 1.0)
        case .horizontal: return UnitPoint(x: 1.0, y: 0.5)
        case .diagonalDown: return UnitPoint(x: 1.0, y: 1.0)
        case .diagonalUp: return UnitPoint(x: 1.0, y: 0.0)
        case .custom(_, let end): return UnitPoint(x: end.x, y: end.y)
        }
    }
}
#endif
