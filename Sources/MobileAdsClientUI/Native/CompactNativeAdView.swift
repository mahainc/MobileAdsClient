//
//  CompactNativeAdView.swift
//  MobileAdsClient
//

#if canImport(UIKit)
    import GoogleMobileAds
    import NativeAdClient
    import UIKit

    public class CompactNativeAdView: NativeAdView {

        public typealias Style = NativeAdClient.Configuration.Style

        public var style: Style {
            didSet { applyStyle() }
        }

        private let metrics: NativeAdClient.Configuration.Metrics

        private let containerPadding: CGFloat = 10

        private lazy var adContainerView: UIView = {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.backgroundColor = .clear
            return view
        }()

        private lazy var adMediaView: MediaView = {
            let view = MediaView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.contentMode = .scaleAspectFill
            view.layer.cornerRadius = 8
            view.layer.masksToBounds = true
            view.clipsToBounds = true
            view.setContentHuggingPriority(.defaultHigh, for: .vertical)
            return view
        }()

        private lazy var adIconImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.accessibilityIdentifier = "Ad Icon Image View"
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            // Corner radius is driven by `metrics.iconCornerRadius` and applied in `setupViews()`.
            imageView.layer.masksToBounds = true
            return imageView
        }()

        private lazy var adHeadlineLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Ad Headline Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            // Title must never be truncated (Google native policy: ≤25 chars, no
            // truncation). Allow it to wrap rather than clip with an ellipsis.
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textColor = .label
            return label
        }()

        private lazy var adSponsorLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Ad Sponsor Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            label.textColor = .secondaryLabel
            return label
        }()

        private lazy var adAttributionLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5))
            label.accessibilityIdentifier = "Ad Attribution Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Ad"
            label.textAlignment = .center
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            label.setContentHuggingPriority(.required, for: .horizontal)
            return label
        }()

        private lazy var adRatingImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.accessibilityIdentifier = "Ad Rating Image View"
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .left
            return imageView
        }()

        private lazy var adBodyLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Ad Body Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            // Body must not be truncated (Google native policy: ≤90 chars, no
            // truncation). Wrap to as many lines as the text needs.
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .left
            label.textColor = .secondaryLabel
            return label
        }()

        private lazy var adStoreLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5))
            label.accessibilityIdentifier = "Ad Store Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            label.textAlignment = .center
            label.text = "App Store"
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            // Low hugging lets the parent stack's `.fill` alignment stretch the
            // chip to the stack's width (= widest chip's intrinsic width). High
            // compression resistance keeps the text from being clipped narrower
            // than it needs.
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            return label
        }()

        private lazy var adPriceLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5))
            label.accessibilityIdentifier = "Ad Price Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            label.textAlignment = .center
            label.text = "Free"
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            return label
        }()

        private lazy var actionButton: UIButton = {
            let button = UIButton()
            // Use `UIButton.Configuration` (iOS 15+) so `contentInsets` — the
            // modern replacement for the deprecated `contentEdgeInsets` — takes
            // effect. Background, foreground, font, and corner radius are all
            // driven via the same configuration in `applyStyle()` / `applyButtonShape()`.
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            button.configuration = config
            button.accessibilityIdentifier = "Ad Action Button"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("Install Now", for: .normal)
            button.isUserInteractionEnabled = false
            return button
        }()

        public init(
            frame: CGRect = .zero,
            style: Style = .compact,
            metrics: NativeAdClient.Configuration.Metrics = .compact
        ) {
            self.style = style
            self.metrics = metrics
            super.init(frame: frame)
            setupViews()
            applyStyle()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            layoutNativeAdGradient()
            // Capsule shape depends on the button's laid-out height, which is only
            // known after Auto Layout resolves. Re-apply every pass; no-op for rect.
            if case .capsule = style.actionButton.shape.mode {
                applyButtonShape()
            }
        }
    }

    // MARK: - Setup

    extension CompactNativeAdView {
        private func setupViews() {
            layer.cornerRadius = metrics.containerCornerRadius
            layer.masksToBounds = true
            clipsToBounds = true

            adIconImageView.layer.cornerRadius = metrics.iconCornerRadius

            let attributionRow = UIStackView()
            attributionRow.axis = .horizontal
            attributionRow.spacing = 8
            attributionRow.alignment = .center
            attributionRow.distribution = .fill
            attributionRow.translatesAutoresizingMaskIntoConstraints = false
            attributionRow.addArrangedSubview(adAttributionLabel)
            attributionRow.addArrangedSubview(adRatingImageView)

            let headlineTextStack = AutoHidingStackView()
            headlineTextStack.accessibilityIdentifier = "Headline Text Stack"
            headlineTextStack.axis = .vertical
            headlineTextStack.spacing = metrics.verticalSpacing
            headlineTextStack.alignment = .leading
            headlineTextStack.distribution = .fill
            headlineTextStack.translatesAutoresizingMaskIntoConstraints = false
            headlineTextStack.addArrangedSubview(adHeadlineLabel)
            headlineTextStack.addArrangedSubview(adSponsorLabel)
            headlineTextStack.addArrangedSubview(attributionRow)

            let headlineStack = AutoHidingStackView()
            headlineStack.accessibilityIdentifier = "Headline Stack"
            headlineStack.axis = .horizontal
            headlineStack.spacing = metrics.horizontalSpacing
            headlineStack.alignment = .center
            headlineStack.distribution = .fill
            headlineStack.translatesAutoresizingMaskIntoConstraints = false
            headlineStack.addArrangedSubview(adIconImageView)
            headlineStack.addArrangedSubview(headlineTextStack)

            let priceStack = AutoHidingStackView()
            priceStack.accessibilityIdentifier = "Price Stack"
            priceStack.axis = .vertical
            priceStack.spacing = 4
            // `.fill` alignment stretches both chips to the stack's width (= the
            // wider chip's intrinsic width), so "App Store" and "Free" render at
            // matching width. `.fillEqually` distribution splits the stack's
            // height evenly between the two children so their heights match too
            // — without this, font descender/ascender differences could cause
            // small height mismatches.
            priceStack.alignment = .fill
            priceStack.distribution = .fillEqually
            priceStack.translatesAutoresizingMaskIntoConstraints = false
            priceStack.setContentHuggingPriority(.required, for: .horizontal)
            priceStack.setContentCompressionResistancePriority(.required, for: .horizontal)
            priceStack.addArrangedSubview(adStoreLabel)
            priceStack.addArrangedSubview(adPriceLabel)

            adBodyLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            adBodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let middleStack = AutoHidingStackView()
            middleStack.accessibilityIdentifier = "Middle Stack"
            middleStack.axis = .horizontal
            middleStack.spacing = metrics.horizontalSpacing
            middleStack.alignment = .center
            middleStack.distribution = .fill
            middleStack.translatesAutoresizingMaskIntoConstraints = false
            middleStack.addArrangedSubview(adBodyLabel)
            middleStack.addArrangedSubview(priceStack)

            // Vertical content stack drives the card height — the card sizes to
            // its content rather than a hard-coded height, so hidden sections
            // (e.g. a no-media creative) fully collapse and the card shrinks.
            let contentStack = UIStackView(arrangedSubviews: [
                adMediaView,
                headlineStack,
                middleStack,
                actionButton,
            ])
            contentStack.accessibilityIdentifier = "Content Stack"
            contentStack.axis = .vertical
            contentStack.spacing = metrics.verticalSpacing
            contentStack.alignment = .fill
            contentStack.distribution = .fill
            contentStack.translatesAutoresizingMaskIntoConstraints = false

            adContainerView.addSubview(contentStack)
            addSubview(adContainerView)

            // Media keeps its slot height when present but yields (priority 999)
            // so the enclosing stack can collapse it to zero for no-media creatives.
            let mediaHeightConstraint = adMediaView.heightAnchor.constraint(equalToConstant: 160)
            mediaHeightConstraint.priority = UILayoutPriority(999)

            NSLayoutConstraint.activate([
                adContainerView.topAnchor.constraint(equalTo: topAnchor, constant: containerPadding),
                adContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                adContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                adContainerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -containerPadding),

                contentStack.topAnchor.constraint(equalTo: adContainerView.topAnchor),
                contentStack.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
                contentStack.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),
                contentStack.bottomAnchor.constraint(equalTo: adContainerView.bottomAnchor),

                mediaHeightConstraint,

                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: metrics.ctaMinHeight)
                    .priority(UILayoutPriority(999)),

                adIconImageView.widthAnchor.constraint(equalToConstant: metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),
            ])
        }

        private func applyStyle() {
            applyBackgroundFill(style.backgrounds.card)

            adHeadlineLabel.font = style.text.headlineFont.resolved
            adSponsorLabel.font = style.text.sponsorFont.resolved
            adBodyLabel.font = style.text.bodyFont.resolved

            var buttonConfig = actionButton.configuration ?? UIButton.Configuration.plain()
            buttonConfig.contentInsets = NSDirectionalEdgeInsets(style.actionButton.contentInsets)
            buttonConfig.background.backgroundColor = style.actionButton.background
            buttonConfig.baseForegroundColor = style.actionButton.title
            let titleFont = style.actionButton.font.resolved
            buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { container in
                var updated = container
                updated.font = titleFont
                return updated
            }
            actionButton.configuration = buttonConfig
            applyButtonShape()

            adAttributionLabel.backgroundColor = style.attribution.background
            adAttributionLabel.textColor = style.attribution.text
            adAttributionLabel.font = style.attribution.font.resolved

            adStoreLabel.backgroundColor = style.store.background
            adStoreLabel.textColor = style.store.text
            adStoreLabel.font = style.store.font.resolved

            adPriceLabel.backgroundColor = style.price.background
            adPriceLabel.textColor = style.price.text
            adPriceLabel.font = style.price.font.resolved
        }

        private func applyButtonShape() {
            var config = actionButton.configuration ?? UIButton.Configuration.plain()
            switch style.actionButton.shape.mode {
                case let .rect(cornerRadius):
                    config.cornerStyle = .fixed
                    config.background.cornerRadius = cornerRadius
                case .capsule:
                    config.cornerStyle = .capsule
            }
            actionButton.configuration = config
        }
    }

    // MARK: - Public API

    extension CompactNativeAdView {
        public func configure(with nativeAd: NativeAd) {
            // Content is set synchronously; the card height self-sizes at the
            // SwiftUI layer via the representable's `sizeThatFits`. (A UIKit
            // transition on `self` here would fight that.)
            applyNativeContentUpdate(animated: false) { [self] in
                updateUI(with: nativeAd)
                updateViewBindings()
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

    // MARK: - Private Helpers

    extension CompactNativeAdView {
        private func updateUI(with nativeAd: NativeAd) {
            adMediaView.mediaContent = nativeAd.mediaContent
            adIconImageView.image = nativeAd.icon?.image
            adHeadlineLabel.text = nativeAd.headline?.capitalizingFirstLetter()
            adSponsorLabel.text = nativeAd.advertiser?.capitalizingFirstLetter()
            adRatingImageView.image = imageOfStars(from: nativeAd.starRating)
            adBodyLabel.text = nativeAd.body?.capitalizingFirstLetter()
            adStoreLabel.text = nativeAd.store?.capitalized
            adPriceLabel.text = nativeAd.price?.capitalized
            actionButton.setTitle(nativeAd.callToAction?.uppercased(), for: .normal)
        }

        private func updateViewBindings() {
            self.mediaView = adMediaView
            self.iconView = adIconImageView
            self.headlineView = adHeadlineLabel
            self.advertiserView = adSponsorLabel
            self.starRatingView = adRatingImageView
            self.storeView = adStoreLabel
            self.priceView = adPriceLabel
            self.callToActionView = actionButton
            self.bodyView = adBodyLabel
        }

        private func updateVisibility(for nativeAd: NativeAd) {
            // `MediaView` shows image ads via the SDK once `mediaContent` is set.
            // Hide the slot when the creative has neither a video nor a meaningful
            // aspect ratio (rare; most served creatives include at least one).
            let mediaContent = nativeAd.mediaContent
            let hasMedia = mediaContent.hasVideoContent || mediaContent.aspectRatio > 0
            adMediaView.isHidden = !hasMedia
            adIconImageView.isHidden = nativeAd.icon?.image == nil
            adHeadlineLabel.isHidden = nativeAd.headline == nil
            adSponsorLabel.isHidden = nativeAd.advertiser == nil
            adRatingImageView.isHidden = nativeAd.starRating == nil
            adBodyLabel.isHidden = nativeAd.body == nil
            adStoreLabel.isHidden = nativeAd.store == nil
            adPriceLabel.isHidden = nativeAd.price == nil
            actionButton.isHidden = nativeAd.callToAction == nil
        }

        private func imageOfStars(from starRating: NSDecimalNumber?) -> UIImage? {
            guard let rating = starRating?.doubleValue else {
                return nil
            }

            if rating >= 5 {
                return UIImage.fromSPM(named: "stars_5")
            } else if rating >= 4.5 {
                return UIImage.fromSPM(named: "stars_4_5")
            } else if rating >= 4 {
                return UIImage.fromSPM(named: "stars_4")
            } else if rating >= 3.5 {
                return UIImage.fromSPM(named: "stars_3_5")
            } else {
                return nil
            }
        }
    }
#endif
