//
//  RowNativeAdView.swift
//  MobileAdsClient
//
//  Row-shaped native ad renderer suitable for in-feed / list insertion.
//  Two layouts (`.inline` = CTA on the right, `.stacked` = CTA below) share
//  the same NativeAd bindings and `NativeAdClient.AdStyle` theming.
//

#if canImport(UIKit)
    import GoogleMobileAds
    import NativeAdClient
    import UIKit

    public class RowNativeAdView: NativeAdView {

        public typealias Style = NativeAdClient.Configuration.Style

        public let configuration: NativeAdClient.Configuration.Row
        public var style: Style {
            didSet { applyStyle() }
        }

        // Convenience accessors so the `setup*` / `updateVisibility` methods stay readable.
        private var layout: NativeAdClient.Configuration.Row.Layout { configuration.layout }
        private var bodyDisplay: NativeAdClient.Configuration.BodyDisplay { configuration.bodyDisplay }
        private var insets: UIEdgeInsets { configuration.insets }

        // Stacked-layout refs retained so `updateCTASpacing()` can re-apply the
        // 10pt breathing-room gap to whichever CTA predecessor is actually visible.
        private var stackedTextStack: UIStackView?
        private var advertiserRow: UIStackView?
        private var bodyContainer: AutoHidingStackView?

        // MARK: - Subviews

        private lazy var adIconImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.accessibilityIdentifier = "Row Native Icon"
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            // Corner radius is driven by `configuration.metrics.iconCornerRadius`
            // and applied in `setupViews()`.
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
            label.accessibilityIdentifier = "Row Native Headline"
            label.translatesAutoresizingMaskIntoConstraints = false
            // Title must never be truncated (Google native policy: ≤25 chars, no
            // truncation). Allow it to wrap rather than clip with an ellipsis.
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }()

        private lazy var adAdvertiserLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Row Native Advertiser"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            return label
        }()

        private lazy var adAttributionLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6))
            label.accessibilityIdentifier = "Row Native Attribution"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Ad"
            label.textAlignment = .center
            // Slight rounding to read as a chip; matches the 2pt vertical padding.
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            label.setContentHuggingPriority(.required, for: .horizontal)
            return label
        }()

        private lazy var adBodyLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Row Native Body"
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
            // `applyButtonShape()` so the styling pipeline is unified.
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            button.configuration = config
            button.accessibilityIdentifier = "Row Native CTA"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("Install", for: .normal)
            // CTA is not user-interactive at the UIKit level — GoogleMobileAds'
            // NativeAdView proxies taps through `callToActionView` binding.
            button.isUserInteractionEnabled = false
            button.setContentHuggingPriority(.required, for: .horizontal)
            // Pair with hugging-required: the CTA must always show its full title
            // even when an `oversizedIcon` metrics override squeezes the inline row.
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            return button
        }()

        // MARK: - Init

        public init(
            frame: CGRect = .zero,
            configuration: NativeAdClient.Configuration.Row = .default
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
            // Dynamic Type changes invalidate the intrinsic content; force a re-layout
            // so the next `updateUIView` pass measures and dispatches a fresh height.
            if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
                setNeedsLayout()
            }
        }
    }

    // MARK: - Setup

    extension RowNativeAdView {
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
            // `.fill` (vs `.leading`) lets multi-line `adBodyLabel` wrap to the
            // stack's full width and, in `.stacked`, lets the appended CTA stretch.
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
            addSubview(row)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
                row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
                row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
                row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),

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

            // The 10pt breathing room above the CTA is applied dynamically by
            // `updateCTASpacing()` after every visibility pass, so it tracks the
            // actual visible-last predecessor (headline / advertiserRow / bodyContainer)
            // rather than getting swallowed when `bodyContainer` hides.
            textStack.addArrangedSubview(actionButton)
            self.stackedTextStack = textStack
            updateCTASpacing()

            let outer = UIStackView(arrangedSubviews: [adIconImageView, textStack])
            outer.axis = .horizontal
            outer.spacing = configuration.metrics.horizontalSpacing
            outer.alignment = .top
            outer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(outer)

            NSLayoutConstraint.activate([
                outer.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
                outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
                outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
                outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),

                adIconImageView.widthAnchor.constraint(equalToConstant: configuration.metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: configuration.metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),

                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.metrics.ctaMinHeight)
                    .priority(UILayoutPriority(999)),
            ])
        }

        private func setupStackedFullCTALayout(textStack: UIStackView) {
            // CTA stretches to the outer V-stack's full width (icon column +
            // horizontal spacing + text column), so lower its horizontal hugging.
            actionButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

            // Inner row: [icon | text column]. CTA is NOT inside textStack here —
            // it lives in the outer V-stack below this row.
            let row = UIStackView(arrangedSubviews: [adIconImageView, textStack])
            row.axis = .horizontal
            row.spacing = configuration.metrics.horizontalSpacing
            row.alignment = .top
            row.translatesAutoresizingMaskIntoConstraints = false

            // Outer column: [icon+text row] above, [CTA] below. The CTA spans the
            // full container width including the area below the icon.
            let outer = UIStackView(arrangedSubviews: [row, actionButton])
            outer.axis = .vertical
            outer.spacing = 10
            outer.alignment = .fill
            outer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(outer)

            // `stackedTextStack` intentionally stays nil — the predecessor-aware
            // `updateCTASpacing()` doesn't apply when the CTA lives in the outer
            // V-stack; its fixed 10pt spacing handles the gap.

            NSLayoutConstraint.activate([
                outer.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
                outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
                outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
                outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),

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

    extension RowNativeAdView {
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

    extension RowNativeAdView {
        public func configure(with nativeAd: NativeAd) {
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

            setNeedsLayout()
            layoutIfNeeded()
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

    extension RowNativeAdView {
        private func updateUI(with nativeAd: NativeAd) {
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
            updateCTASpacing()
        }

        private func updateCTASpacing() {
            // Only relevant for stacked layout — inline keeps the CTA outside `textStack`.
            guard layout.mode == .stacked,
                let textStack = stackedTextStack,
                let advertiserRow,
                let bodyContainer
            else { return }

            // Reset all predecessor spacings so a previous "last visible" doesn't
            // keep its 10pt after a later visibility change moves the tail elsewhere.
            let predecessors: [UIView] = [adHeadlineLabel, advertiserRow, bodyContainer]
            for view in predecessors {
                textStack.setCustomSpacing(UIStackView.spacingUseDefault, after: view)
            }

            // Find the actually-visible last item before the CTA. We use
            // `adBodyLabel.isHidden` as the sync proxy for `bodyContainer`'s
            // eventual hidden state — `AutoHidingStackView` updates its own
            // `isHidden` on the next runloop tick, so reading `bodyContainer.isHidden`
            // immediately after assignment can return a stale value.
            let visibilityChain: [(view: UIView, isVisible: Bool)] = [
                (adHeadlineLabel, !adHeadlineLabel.isHidden),
                (advertiserRow, true),  // Ad chip is fixed text
                (bodyContainer, !adBodyLabel.isHidden),  // sync proxy for bodyContainer
            ]

            if let lastVisible = visibilityChain.reversed().first(where: { $0.isVisible }) {
                textStack.setCustomSpacing(10, after: lastVisible.view)
            }
        }
    }

#endif
