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

            public static func == (
                lhs: AnyAdLoaderOption,
                rhs: AnyAdLoaderOption
            ) -> Bool {
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
            public protocol Kind: Sendable, Equatable {}

            // MARK: - Shared building blocks

            public struct Gradient: Sendable, Equatable, Hashable {
                public enum Direction: Sendable, Equatable, Hashable {
                    case vertical
                    case horizontal
                    case diagonalDown
                    case diagonalUp
                    case custom(start: CGPoint, end: CGPoint)
                }

                public var colors: [UIColor]
                public var locations: [NSNumber]?
                public var direction: Direction

                public init(
                    colors: [UIColor],
                    locations: [NSNumber]? = nil,
                    direction: Direction = .vertical
                ) {
                    self.colors = colors
                    self.locations = locations
                    self.direction = direction
                }
            }

            public struct BackgroundFill: Sendable, Equatable, Hashable {
                public enum Mode: Sendable, Equatable, Hashable {
                    case solid(UIColor)
                    case gradient(Gradient)
                }

                public var mode: Mode

                public init(mode: Mode) {
                    self.mode = mode
                }

                public static func solid(_ color: UIColor) -> BackgroundFill {
                    BackgroundFill(mode: .solid(color))
                }

                public static func gradient(_ gradient: Gradient) -> BackgroundFill {
                    BackgroundFill(mode: .gradient(gradient))
                }

                public static func gradient(
                    colors: [UIColor],
                    locations: [NSNumber]? = nil,
                    direction: Gradient.Direction = .vertical
                ) -> BackgroundFill {
                    BackgroundFill(
                        mode: .gradient(
                            Gradient(colors: colors, locations: locations, direction: direction)
                        )
                    )
                }
            }

            public struct AdFont: Sendable, Equatable, Hashable {
                public enum Mode: Sendable, Equatable, Hashable {
                    case textStyle(UIFont.TextStyle, weight: UIFont.Weight?)
                    case system(size: CGFloat, weight: UIFont.Weight, scaledFor: UIFont.TextStyle?)
                    case custom(name: String, size: CGFloat, scaledFor: UIFont.TextStyle?)
                    case fixed(UIFont)
                }

                public var mode: Mode

                public init(mode: Mode) {
                    self.mode = mode
                }

                public static func textStyle(
                    _ style: UIFont.TextStyle,
                    weight: UIFont.Weight? = nil
                ) -> AdFont {
                    AdFont(mode: .textStyle(style, weight: weight))
                }

                public static func system(
                    size: CGFloat,
                    weight: UIFont.Weight = .regular,
                    scaledFor: UIFont.TextStyle? = nil
                ) -> AdFont {
                    AdFont(mode: .system(size: size, weight: weight, scaledFor: scaledFor))
                }

                public static func custom(
                    name: String,
                    size: CGFloat,
                    scaledFor: UIFont.TextStyle? = nil
                ) -> AdFont {
                    AdFont(mode: .custom(name: name, size: size, scaledFor: scaledFor))
                }

                public static func fixed(_ font: UIFont) -> AdFont {
                    AdFont(mode: .fixed(font))
                }
            }

            public struct Style: Sendable, Equatable, Hashable {
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

                public struct Backgrounds: Sendable, Equatable, Hashable {
                    public var card: BackgroundFill
                    public var content: BackgroundFill

                    public init(
                        card: BackgroundFill = .solid(.secondarySystemBackground),
                        content: BackgroundFill = .solid(.clear)
                    ) {
                        self.card = card
                        self.content = content
                    }

                    public init(
                        card: UIColor,
                        content: UIColor = .clear
                    ) {
                        self.init(card: .solid(card), content: .solid(content))
                    }
                }

                public struct TextColors: Sendable, Equatable, Hashable {
                    public var headline: UIColor
                    public var body: UIColor
                    public var sponsor: UIColor
                    public var headlineFont: AdFont
                    public var bodyFont: AdFont
                    public var sponsorFont: AdFont

                    public init(
                        headline: UIColor = .label,
                        body: UIColor = .secondaryLabel,
                        sponsor: UIColor = .secondaryLabel,
                        headlineFont: AdFont = .textStyle(.headline),
                        bodyFont: AdFont = .textStyle(.callout),
                        sponsorFont: AdFont = .textStyle(.subheadline)
                    ) {
                        self.headline = headline
                        self.body = body
                        self.sponsor = sponsor
                        self.headlineFont = headlineFont
                        self.bodyFont = bodyFont
                        self.sponsorFont = sponsorFont
                    }
                }

                public struct ButtonStyle: Sendable, Equatable, Hashable {
                    public var background: UIColor
                    public var title: UIColor
                    public var shape: ButtonShape
                    public var font: AdFont
                    public var contentInsets: UIEdgeInsets

                    public init(
                        background: UIColor = .systemBlue,
                        title: UIColor = .white,
                        shape: ButtonShape = .rect(cornerRadius: 8),
                        font: AdFont = .textStyle(.headline),
                        contentInsets: UIEdgeInsets = .init(top: 6, left: 10, bottom: 6, right: 10)
                    ) {
                        self.background = background
                        self.title = title
                        self.shape = shape
                        self.font = font
                        self.contentInsets = contentInsets
                    }

                    public func hash(into hasher: inout Hasher) {
                        hasher.combine(background)
                        hasher.combine(title)
                        hasher.combine(shape)
                        hasher.combine(font)
                        hasher.combine(contentInsets.top)
                        hasher.combine(contentInsets.left)
                        hasher.combine(contentInsets.bottom)
                        hasher.combine(contentInsets.right)
                    }
                }

                public struct ChipColors: Sendable, Equatable, Hashable {
                    public var background: UIColor
                    public var text: UIColor
                    public var font: AdFont

                    public init(
                        background: UIColor,
                        text: UIColor,
                        font: AdFont = .textStyle(.caption2)
                    ) {
                        self.background = background
                        self.text = text
                        self.font = font
                    }
                }

                public var backgrounds: Backgrounds
                public var text: TextColors
                public var actionButton: ButtonStyle
                public var attribution: ChipColors
                public var store: ChipColors
                public var price: ChipColors
                public var closeButton: ChipColors

                public init(
                    backgrounds: Backgrounds = Backgrounds(),
                    text: TextColors = TextColors(),
                    actionButton: ButtonStyle = ButtonStyle(),
                    attribution: ChipColors = ChipColors(background: .systemBlue, text: .white),
                    store: ChipColors = ChipColors(background: .systemGreen, text: .white),
                    price: ChipColors = ChipColors(background: .systemGreen, text: .white),
                    closeButton: ChipColors = ChipColors(
                        background: UIColor.label.withAlphaComponent(0.08),
                        text: .label
                    )
                ) {
                    self.backgrounds = backgrounds
                    self.text = text
                    self.actionButton = actionButton
                    self.attribution = attribution
                    self.store = store
                    self.price = price
                    self.closeButton = closeButton
                }

                public static let compact: Style = .init(
                    text: .init(
                        headlineFont: .textStyle(.subheadline),
                        bodyFont: .textStyle(.footnote),
                        sponsorFont: .system(size: 13, weight: .regular, scaledFor: .subheadline)
                    ),
                    actionButton: .init(font: .textStyle(.headline)),
                    attribution: .init(
                        background: .systemBlue,
                        text: .white,
                        font: .textStyle(.caption2)
                    ),
                    store: .init(
                        background: .systemGreen,
                        text: .white,
                        font: .system(size: 11, weight: .semibold, scaledFor: .caption2)
                    ),
                    price: .init(
                        background: .systemGreen,
                        text: .white,
                        font: .system(size: 11, weight: .semibold, scaledFor: .caption2)
                    )
                )

                // Immersive full-bleed layout: media fills the screen and text
                // overlays a bottom dark scrim, so the foreground text is light
                // regardless of the creative. Card stays dark for the brief
                // pre-media frame / no-media fallback behind the scrim.
                public static let fullScreen: Style = .init(
                    backgrounds: .init(card: .black, content: .clear),
                    text: .init(
                        headline: .white,
                        body: UIColor.white.withAlphaComponent(0.9),
                        sponsor: UIColor.white.withAlphaComponent(0.8),
                        headlineFont: .textStyle(.headline, weight: .bold),
                        bodyFont: .textStyle(.subheadline),
                        sponsorFont: .textStyle(.caption1)
                    ),
                    actionButton: .init(
                        background: .systemBlue,
                        title: .white,
                        shape: .capsule,
                        font: .textStyle(.subheadline, weight: .semibold)
                    ),
                    attribution: .init(
                        background: .systemBlue,
                        text: .white,
                        font: .textStyle(.caption2, weight: .semibold)
                    ),
                    closeButton: .init(
                        background: UIColor.black.withAlphaComponent(0.25),
                        text: .white
                    )
                )

                public static let advanced: Style = .init(
                    backgrounds: .init(
                        card: .clear,
                        content: UIColor(red: 234 / 255, green: 240 / 255, blue: 253 / 255, alpha: 1)
                    ),
                    text: .init(
                        headline: UIColor(red: 66 / 255, green: 66 / 255, blue: 66 / 255, alpha: 1),
                        body: .secondaryLabel,
                        sponsor: .secondaryLabel,
                        headlineFont: .system(size: 16, weight: .bold),
                        bodyFont: .system(size: 13, weight: .regular),
                        sponsorFont: .system(size: 14, weight: .medium)
                    ),
                    actionButton: .init(
                        background: .systemBlue.withAlphaComponent(0.15),
                        title: .systemBlue,
                        shape: .rect(cornerRadius: 5),
                        font: .system(size: 15, weight: .bold)
                    ),
                    attribution: .init(
                        background: .clear,
                        text: .systemBlue,
                        font: .system(size: 13, weight: .semibold)
                    ),
                    store: .init(
                        background: .systemGreen.withAlphaComponent(0.15),
                        text: .systemGreen,
                        font: .system(size: 15, weight: .bold)
                    ),
                    price: .init(
                        background: .systemGreen.withAlphaComponent(0.15),
                        text: .systemGreen,
                        font: .system(size: 15, weight: .bold)
                    )
                )

                public static let custom: Style = .init(
                    backgrounds: .init(
                        card: .clear,
                        content: UIColor(red: 122 / 255, green: 159 / 255, blue: 126 / 255, alpha: 1)
                    ),
                    text: .init(
                        headline: UIColor(red: 66 / 255, green: 66 / 255, blue: 66 / 255, alpha: 1),
                        body: .secondaryLabel,
                        sponsor: .secondaryLabel
                    ),
                    actionButton: .init(
                        background: .systemBlue,
                        title: .white,
                        shape: .rect(cornerRadius: 5),
                        font: .textStyle(.title3)
                    ),
                    attribution: .init(
                        background: .systemBlue,
                        text: .white,
                        font: .textStyle(.footnote)
                    ),
                    store: .init(
                        background: .systemGreen,
                        text: .white,
                        font: .textStyle(.subheadline)
                    ),
                    price: .init(
                        background: .systemGreen,
                        text: .white,
                        font: .textStyle(.subheadline)
                    )
                )

                public static let row: Style = .init(
                    backgrounds: .init(card: .secondarySystemBackground, content: .clear),
                    text: .init(
                        headlineFont: .textStyle(.subheadline, weight: .semibold),
                        bodyFont: .textStyle(.footnote),
                        sponsorFont: .textStyle(.caption1)
                    ),
                    actionButton: .init(
                        background: .systemBlue,
                        title: .white,
                        shape: .capsule,
                        font: .textStyle(.subheadline, weight: .semibold)
                    ),
                    attribution: .init(
                        background: .systemGray5,
                        text: .secondaryLabel,
                        font: .textStyle(.caption2, weight: .semibold)
                    )
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
                public var containerCornerRadius: CGFloat
                public var ctaMinHeight: CGFloat
                public var horizontalSpacing: CGFloat
                public var verticalSpacing: CGFloat

                public init(
                    iconSize: CGSize = CGSize(width: 56, height: 56),
                    iconCornerRadius: CGFloat = 10,
                    containerCornerRadius: CGFloat = 12,
                    ctaMinHeight: CGFloat = 36,
                    horizontalSpacing: CGFloat = 12,
                    verticalSpacing: CGFloat = 4
                ) {
                    self.iconSize = iconSize
                    self.iconCornerRadius = iconCornerRadius
                    self.containerCornerRadius = containerCornerRadius
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
                    containerCornerRadius: 0,
                    ctaMinHeight: 44,
                    horizontalSpacing: 12,
                    verticalSpacing: 8
                )
                public static let fullScreen = Metrics(
                    iconSize: CGSize(width: 56, height: 56),
                    iconCornerRadius: 12,
                    containerCornerRadius: 0,
                    ctaMinHeight: 56,
                    horizontalSpacing: 12,
                    verticalSpacing: 2
                )
                public static let advanced = Metrics(
                    iconSize: CGSize(width: 50, height: 50),
                    iconCornerRadius: 5,
                    containerCornerRadius: 5,
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
                        case stackedFullCTA
                    }

                    public var mode: Mode

                    public init(mode: Mode = .inline) {
                        self.mode = mode
                    }

                    public static let inline = Layout(mode: .inline)
                    public static let stacked = Layout(mode: .stacked)
                    public static let stackedFullCTA = Layout(mode: .stackedFullCTA)
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
                    let stackedLike = layout.mode == .stacked || layout.mode == .stackedFullCTA
                    self.metrics = metrics ?? (stackedLike ? .rowStacked : .row)
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

            public struct RowMedia: Kind, Hashable {
                public typealias Layout = Row.Layout

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
                    let stackedLike = layout.mode == .stacked || layout.mode == .stackedFullCTA
                    self.metrics = metrics ?? (stackedLike ? .rowStacked : .row)
                }

                public static let `default` = RowMedia()
                public static let inline = RowMedia(layout: .inline)
                public static let stacked = RowMedia(layout: .stacked)
                public static let stackedFullCTA = RowMedia(layout: .stackedFullCTA)

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

            // Drives the immersive full-bleed `FullScreenNativeAdView`. Unlike the
            // in-feed templates this one isn't store/`AnyConfiguration`-selectable —
            // it's passed directly to `FullScreenNativeView` / the presenter — but
            // it shares the same `style` + `metrics` + `bodyDisplay` shape so the
            // renderer reads config instead of hardcoded values.
            public struct FullScreen: Kind, Hashable {
                /// How the media creative fills its frame.
                public enum MediaContentMode: Sendable, Equatable, Hashable {
                    /// Crops to fill the frame edge-to-edge (no letterboxing). Best
                    /// for the immersive full-bleed look — parts of the creative may
                    /// be cropped. Maps to `.scaleAspectFill`.
                    case fill
                    /// Fits the whole creative inside the frame; any leftover space
                    /// shows the card/scrim background (letterboxed). Maps to
                    /// `.scaleAspectFit`.
                    case fit
                }

                public var style: Style
                public var bodyDisplay: BodyDisplay
                public var metrics: Metrics
                /// When `true` the media view bleeds to every screen edge (under the
                /// notch + home indicator). When `false` (default) the media is
                /// inset to the safe area instead.
                public var mediaIgnoresSafeArea: Bool
                /// How the media creative fills its frame (default `.fit`).
                public var mediaContentMode: MediaContentMode
                /// Seconds the ad stays locked before the close button appears. While
                /// counting down, a "closes in Ns" label shows in place of the close
                /// button. `0` = no gate (close button shown immediately).
                public var closeCountdown: Int

                public init(
                    style: Style = .fullScreen,
                    bodyDisplay: BodyDisplay = .truncated(lines: 3),
                    metrics: Metrics = .fullScreen,
                    mediaIgnoresSafeArea: Bool = false,
                    mediaContentMode: MediaContentMode = .fit,
                    closeCountdown: Int = 5
                ) {
                    self.style = style
                    self.bodyDisplay = bodyDisplay
                    self.metrics = metrics
                    self.mediaIgnoresSafeArea = mediaIgnoresSafeArea
                    self.mediaContentMode = mediaContentMode
                    self.closeCountdown = closeCountdown
                }

                public static let `default` = FullScreen()

                public func hash(into hasher: inout Hasher) {
                    hasher.combine(bodyDisplay)
                    hasher.combine(metrics)
                    hasher.combine(mediaIgnoresSafeArea)
                    hasher.combine(mediaContentMode)
                    hasher.combine(closeCountdown)
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

            public static func == (
                lhs: AnyConfiguration,
                rhs: AnyConfiguration
            ) -> Bool {
                lhs.equals(rhs.base)
            }
        }
    }
#endif
