//
//  RowMediaNativeAdView.swift
//  MobileAdsClient
//
//  Row-shaped native ad renderer with a 16:9 `MediaView` block above the
//  icon / headline / body / CTA row. Mirrors `RowNativeAdView`'s three
//  layouts (`.inline` / `.stacked` / `.stackedFullCTA`); the only structural
//  delta is the outer vertical stack `[mediaView, rowContent]`.
//

#if canImport(UIKit)
    import GoogleMobileAds
    import NativeAdClient
    import UIKit

    public class RowMediaNativeAdView: NativeAdView {

        public typealias Style = NativeAdClient.Configuration.Style

        public let configuration: NativeAdClient.Configuration.RowMedia
        public var style: Style {
            didSet { applyStyle() }
        }

        private var layout: NativeAdClient.Configuration.RowMedia.Layout { configuration.layout }
        private var bodyDisplay: NativeAdClient.Configuration.BodyDisplay { configuration.bodyDisplay }
        private var insets: UIEdgeInsets { configuration.insets }

        // Stacked-layout refs retained so `updateCTASpacing()` can re-apply the
        // 10pt breathing-room gap to whichever CTA predecessor is actually visible.
        private var stackedTextStack: UIStackView?
        private var advertiserRow: UIStackView?
        private var bodyContainer: AutoHidingStackView?

        // Fixed gap between the media block and the row content — kept distinct
        // from `metrics.verticalSpacing` (which governs the inner text stack)
        // so the media→row breathing room stays predictable.
        private let mediaToRowSpacing: CGFloat = 10

        // MARK: - Subviews

        private lazy var adMediaView: MediaView = {
            let view = MediaView()
            view.accessibilityIdentifier = "Row-Media Native Media"
            view.translatesAutoresizingMaskIntoConstraints = false
            view.contentMode = .scaleAspectFill
            view.layer.masksToBounds = true
            return view
        }()

        private lazy var adIconImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.accessibilityIdentifier = "Row-Media Native Icon"
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.layer.masksToBounds = true
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            // Below the 999-priority width constraint so the fixed `iconSize`
            // (a square 1:1, per Google's native icon spec) wins over the
            // image's intrinsic width instead of stretching the icon wide.
            imageView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            return imageView
        }()

        private lazy var adHeadlineLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Row-Media Native Headline"
            label.translatesAutoresizingMaskIntoConstraints = false
            // Title must never be truncated (Google native policy: ≤25 chars, no
            // truncation). Allow it to wrap rather than clip with an ellipsis.
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }()

        private lazy var adAdvertiserLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Row-Media Native Advertiser"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            return label
        }()

        private lazy var adAttributionLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6))
            label.accessibilityIdentifier = "Row-Media Native Attribution"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Ad"
            label.textAlignment = .center
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            label.setContentHuggingPriority(.required, for: .horizontal)
            return label
        }()

        private lazy var adBodyLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Row-Media Native Body"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.lineBreakMode = .byTruncatingTail
            return label
        }()

        private lazy var actionButton: UIButton = {
            let button = UIButton(type: .system)
            // Use `UIButton.Configuration` (iOS 15+) so `contentInsets` — the
            // modern replacement for the deprecated `contentEdgeInsets` — takes
            // effect. Background, foreground, font, and corner radius are all
            // driven via the same configuration in `applyStyle()` /
            // `applyButtonShape()`.
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            button.configuration = config
            button.accessibilityIdentifier = "Row-Media Native CTA"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("Install", for: .normal)
            button.isUserInteractionEnabled = false
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            return button
        }()

        // MARK: - Init

        public init(
            frame: CGRect = .zero,
            configuration: NativeAdClient.Configuration.RowMedia = .default
        ) {
            self.configuration = configuration
            self.style = configuration.style
            super.init(frame: frame)
            setupViews()
            updateViewBindings()
            applyStyle()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            layoutNativeAdGradient()
        }

        public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
                setNeedsLayout()
            }
        }
    }

    // MARK: - Setup

    extension RowMediaNativeAdView {
        private func setupViews() {
            layer.cornerRadius = configuration.metrics.containerCornerRadius
            layer.masksToBounds = true

            adIconImageView.layer.cornerRadius = configuration.metrics.iconCornerRadius

            switch bodyDisplay.mode {
                case .hidden, .full:
                    adBodyLabel.numberOfLines = 0
                case .truncated(let lines):
                    adBodyLabel.numberOfLines = max(1, lines)
            }

            // Hug the advertiser text so it never stretches to fill the row's full
            // width; a trailing flexible spacer absorbs the leftover space instead,
            // keeping the "Ad" chip pinned 6pt after the name regardless of
            // how short the advertiser name is.
            adAdvertiserLabel.setContentHuggingPriority(.required, for: .horizontal)

            let trailingSpacer = UIView()
            trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            trailingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let advertiserRow = UIStackView(arrangedSubviews: [adAdvertiserLabel, adAttributionLabel, trailingSpacer])
            advertiserRow.axis = .horizontal
            advertiserRow.spacing = 6
            advertiserRow.alignment = .center
            advertiserRow.translatesAutoresizingMaskIntoConstraints = false

            let bodyContainer = AutoHidingStackView(arrangedSubviews: [adBodyLabel])
            bodyContainer.axis = .vertical
            bodyContainer.translatesAutoresizingMaskIntoConstraints = false

            self.advertiserRow = advertiserRow
            self.bodyContainer = bodyContainer

            let textStack = UIStackView(arrangedSubviews: [adHeadlineLabel, advertiserRow, bodyContainer])
            textStack.axis = .vertical
            textStack.spacing = configuration.metrics.verticalSpacing
            textStack.alignment = .fill
            textStack.translatesAutoresizingMaskIntoConstraints = false
            textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            switch layout.mode {
                case .inline:
                    setupInlineLayout(textStack: textStack)
                case .stacked:
                    setupStackedLayout(textStack: textStack)
                case .stackedFullCTA:
                    setupStackedFullCTALayout(textStack: textStack)
            }
        }

        private func setupInlineLayout(textStack: UIStackView) {
            let row = UIStackView(arrangedSubviews: [adIconImageView, textStack, actionButton])
            row.axis = .horizontal
            row.spacing = configuration.metrics.horizontalSpacing
            row.alignment = .center
            row.translatesAutoresizingMaskIntoConstraints = false

            let outer = UIStackView(arrangedSubviews: [adMediaView, row])
            outer.axis = .vertical
            outer.spacing = mediaToRowSpacing
            outer.alignment = .fill
            outer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(outer)

            NSLayoutConstraint.activate([
                outer.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
                outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
                outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
                outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),

                // 16:9 lock — media height tracks media width regardless of what
                // aspect ratio the actual creative ships with.
                adMediaView.heightAnchor.constraint(equalTo: adMediaView.widthAnchor, multiplier: 9.0 / 16.0)
                    .priority(UILayoutPriority(999)),

                adIconImageView.widthAnchor.constraint(equalToConstant: configuration.metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: configuration.metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),

                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.metrics.ctaMinHeight)
                    .priority(UILayoutPriority(999)),
            ])
        }

        private func setupStackedLayout(textStack: UIStackView) {
            // CTA lives inside the inner text column and must stretch to its full
            // width — lower the button's horizontal hugging so `.fill` alignment wins.
            actionButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

            textStack.addArrangedSubview(actionButton)
            self.stackedTextStack = textStack
            updateCTASpacing()

            let innerRow = UIStackView(arrangedSubviews: [adIconImageView, textStack])
            innerRow.axis = .horizontal
            innerRow.spacing = configuration.metrics.horizontalSpacing
            innerRow.alignment = .top
            innerRow.translatesAutoresizingMaskIntoConstraints = false

            let outer = UIStackView(arrangedSubviews: [adMediaView, innerRow])
            outer.axis = .vertical
            outer.spacing = mediaToRowSpacing
            outer.alignment = .fill
            outer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(outer)

            NSLayoutConstraint.activate([
                outer.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
                outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
                outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
                outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),

                adMediaView.heightAnchor.constraint(equalTo: adMediaView.widthAnchor, multiplier: 9.0 / 16.0)
                    .priority(UILayoutPriority(999)),

                adIconImageView.widthAnchor.constraint(equalToConstant: configuration.metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: configuration.metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),

                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.metrics.ctaMinHeight)
                    .priority(UILayoutPriority(999)),
            ])
        }

        private func setupStackedFullCTALayout(textStack: UIStackView) {
            actionButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let innerRow = UIStackView(arrangedSubviews: [adIconImageView, textStack])
            innerRow.axis = .horizontal
            innerRow.spacing = configuration.metrics.horizontalSpacing
            innerRow.alignment = .top
            innerRow.translatesAutoresizingMaskIntoConstraints = false

            // Mirror RowNativeAdView's stackedFullCTA: a V-stack of [icon+text row, CTA]
            // with a fixed 10pt gap before the full-width CTA.
            let rowAndCTA = UIStackView(arrangedSubviews: [innerRow, actionButton])
            rowAndCTA.axis = .vertical
            rowAndCTA.spacing = 10
            rowAndCTA.alignment = .fill
            rowAndCTA.translatesAutoresizingMaskIntoConstraints = false

            let outer = UIStackView(arrangedSubviews: [adMediaView, rowAndCTA])
            outer.axis = .vertical
            outer.spacing = mediaToRowSpacing
            outer.alignment = .fill
            outer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(outer)

            NSLayoutConstraint.activate([
                outer.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
                outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
                outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
                outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),

                adMediaView.heightAnchor.constraint(equalTo: adMediaView.widthAnchor, multiplier: 9.0 / 16.0)
                    .priority(UILayoutPriority(999)),

                adIconImageView.widthAnchor.constraint(equalToConstant: configuration.metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: configuration.metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),

                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.metrics.ctaMinHeight)
                    .priority(UILayoutPriority(999)),
            ])
        }
    }

    // MARK: - Styling

    extension RowMediaNativeAdView {
        private func applyStyle() {
            applyBackgroundFill(style.backgrounds.card)

            adHeadlineLabel.textColor = style.text.headline
            adHeadlineLabel.font = style.text.headlineFont.resolved
            adAdvertiserLabel.textColor = style.text.sponsor
            adAdvertiserLabel.font = style.text.sponsorFont.resolved
            adBodyLabel.textColor = style.text.body
            adBodyLabel.font = style.text.bodyFont.resolved

            adAttributionLabel.backgroundColor = style.attribution.background
            adAttributionLabel.textColor = style.attribution.text
            adAttributionLabel.font = style.attribution.font.resolved

            var buttonConfig = actionButton.configuration ?? UIButton.Configuration.plain()
            buttonConfig.contentInsets = NSDirectionalEdgeInsets(style.actionButton.contentInsets)
            buttonConfig.background.backgroundColor = style.actionButton.background
            buttonConfig.baseForegroundColor = style.actionButton.title
            let titleFont = style.actionButton.font.resolved
            buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { container in
                var c = container
                c.font = titleFont
                return c
            }
            actionButton.configuration = buttonConfig
            applyButtonShape()
        }

        private func applyButtonShape() {
            var config = actionButton.configuration ?? UIButton.Configuration.plain()
            switch style.actionButton.shape.mode {
                case let .rect(cornerRadius):
                    config.cornerStyle = .fixed
                    config.background.cornerRadius = cornerRadius
                case .capsule:
                    // `.capsule` lets UIButton derive the radius from its current
                    // bounds; no manual re-apply needed once the frame settles.
                    config.cornerStyle = .capsule
            }
            actionButton.configuration = config
        }
    }

    // MARK: - Public API

    extension RowMediaNativeAdView {
        public func configure(with nativeAd: NativeAd) {
            // Content is set synchronously; the card height eases at the SwiftUI
            // layer via `.frame(height: store.adHeight)`. (A UIKit transition on
            // `self` here would fight that frame animation on the same layer.)
            applyNativeContentUpdate(animated: false) { [self] in
                updateUI(with: nativeAd)
                updateVisibility(for: nativeAd)
                self.nativeAd = nativeAd

                // The Google SDK rebinds the registered `iconView` when `nativeAd`
                // is assigned and may reset its image-rendering knobs. Re-assert
                // them here so the icon stays cropped-and-filled inside its slot
                // instead of being letterboxed at the asset's native aspect ratio.
                adIconImageView.contentMode = .scaleAspectFill
                adIconImageView.clipsToBounds = true
                adIconImageView.layer.masksToBounds = true
            }
        }

        public func calculateTotalHeight(fittingWidth: CGFloat) -> CGFloat {
            let target = CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height)
            return systemLayoutSizeFitting(
                target,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        }
    }

    // MARK: - Private helpers

    extension RowMediaNativeAdView {
        private func updateUI(with nativeAd: NativeAd) {
            adMediaView.mediaContent = nativeAd.mediaContent
            adIconImageView.image = nativeAd.icon?.image
            adHeadlineLabel.text = nativeAd.headline?.capitalizingFirstLetter()
            adAdvertiserLabel.text = (nativeAd.advertiser ?? nativeAd.store)?.capitalizingFirstLetter()
            adBodyLabel.text = nativeAd.body?.capitalizingFirstLetter()
            actionButton.setTitle(nativeAd.callToAction, for: .normal)
        }

        private func updateViewBindings() {
            self.iconView = adIconImageView
            self.headlineView = adHeadlineLabel
            self.advertiserView = adAdvertiserLabel
            self.bodyView = adBodyLabel
            self.callToActionView = actionButton
            self.mediaView = adMediaView
        }

        private func updateVisibility(for nativeAd: NativeAd) {
            adIconImageView.isHidden = nativeAd.icon?.image == nil
            adHeadlineLabel.isHidden = nativeAd.headline == nil
            adAdvertiserLabel.isHidden = (nativeAd.advertiser ?? nativeAd.store) == nil
            let bodyHidden: Bool
            switch bodyDisplay.mode {
                case .hidden:
                    bodyHidden = true
                case .full, .truncated:
                    bodyHidden = nativeAd.body == nil
            }
            adBodyLabel.isHidden = bodyHidden
            actionButton.isHidden = nativeAd.callToAction == nil
            // Collapse the media block when the creative has neither a video nor
            // a meaningful aspect ratio. Video creatives can report `aspectRatio
            // == 0` until playback metadata arrives, so checking `hasVideoContent`
            // separately keeps the slot visible for them.
            let mediaContent = nativeAd.mediaContent
            adMediaView.isHidden = !(mediaContent.hasVideoContent || mediaContent.aspectRatio > 0)
            updateCTASpacing()
        }

        private func updateCTASpacing() {
            guard layout.mode == .stacked,
                let textStack = stackedTextStack,
                let advertiserRow,
                let bodyContainer
            else { return }

            let predecessors: [UIView] = [adHeadlineLabel, advertiserRow, bodyContainer]
            for view in predecessors {
                textStack.setCustomSpacing(UIStackView.spacingUseDefault, after: view)
            }

            let visibilityChain: [(view: UIView, isVisible: Bool)] = [
                (adHeadlineLabel, !adHeadlineLabel.isHidden),
                (advertiserRow, true),
                (bodyContainer, !adBodyLabel.isHidden),
            ]

            if let lastVisible = visibilityChain.reversed().first(where: { $0.isVisible }) {
                textStack.setCustomSpacing(10, after: lastVisible.view)
            }
        }
    }

#endif
