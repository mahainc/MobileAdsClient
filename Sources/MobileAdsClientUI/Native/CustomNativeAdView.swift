//
//  CustomNativeAdView.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 17/2/25.
//

#if canImport(UIKit)
    import GoogleMobileAds
    import NativeAdClient
    import UIKit

    public class CustomNativeAdView: NativeAdView {

        public typealias Style = NativeAdClient.Configuration.Style

        public var style: Style {
            didSet { applyStyle() }
        }

        private let metrics: NativeAdClient.Configuration.Metrics

        private var heightConstraint: NSLayoutConstraint!
        private var currentMultiplier: CGFloat = 9.0 / 16.0
        private let defaultSpacing: CGFloat = 16

        private lazy var adContainerView: UIView = {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.layer.cornerRadius = 0
            view.layer.masksToBounds = true
            view.clipsToBounds = true

            return view
        }()

        private lazy var adHeadlineLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Ad Headline Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.text = "Ad Headline"

            return label
        }()

        private lazy var adSponsorLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Ad Sponsor Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.text = "Ad Sponsor"

            return label
        }()

        private lazy var adAttributionLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
            label.accessibilityIdentifier = "Ad Attribution Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Ad"
            label.textAlignment = .center
            label.layer.cornerRadius = 5
            label.layer.masksToBounds = true

            return label
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

        private lazy var adRatingImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.accessibilityIdentifier = "Ad Rating Image View"
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .left

            return imageView
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

        private lazy var adBodyLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Ad Body Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.textAlignment = .left

            return label
        }()

        private lazy var adStoreLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
            label.accessibilityIdentifier = "Ad Store Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.textAlignment = .center
            label.text = "App Store"
            label.layer.cornerRadius = 5
            label.layer.masksToBounds = true

            return label
        }()

        private lazy var adPriceLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
            label.accessibilityIdentifier = "Ad Price Label"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.textAlignment = .center
            label.text = "Free"
            label.layer.cornerRadius = 5
            label.layer.masksToBounds = true

            return label
        }()

        private lazy var contentView: MediaView = {
            let view = MediaView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.layer.masksToBounds = true

            return view
        }()

        private lazy var headlineStack: AutoHidingStackView = {
            let stack = AutoHidingStackView()
            stack.accessibilityIdentifier = "Headline Stack"
            stack.axis = .horizontal
            stack.spacing = metrics.horizontalSpacing
            stack.alignment = .center
            stack.distribution = .fill
            stack.translatesAutoresizingMaskIntoConstraints = false

            return stack
        }()

        private lazy var emptyView: UIView = {
            let view = UIView()
            view.backgroundColor = .purple
            return view
        }()

        public init(
            frame: CGRect = .zero,
            style: Style = .custom,
            metrics: NativeAdClient.Configuration.Metrics = .custom
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
            adContainerView.layoutNativeAdGradient()
            if case .capsule = style.actionButton.shape.mode {
                applyButtonShape()
            }
        }
    }

    // MARK: - Private Methods

    extension CustomNativeAdView {
        private func setupViews() {
            addBlur(style: .dark)
            layer.cornerRadius = metrics.containerCornerRadius
            layer.masksToBounds = true

            adIconImageView.layer.cornerRadius = metrics.iconCornerRadius

            let storeStack = AutoHidingStackView()
            storeStack.accessibilityIdentifier = "Store Stack"
            storeStack.axis = .horizontal
            storeStack.spacing = 8
            storeStack.alignment = .center
            storeStack.distribution = .fill
            storeStack.translatesAutoresizingMaskIntoConstraints = false
            storeStack.addArrangedSubview(adStoreLabel)
            storeStack.addArrangedSubview(adPriceLabel)

            let attributionStack = UIStackView()
            attributionStack.accessibilityIdentifier = "Attribution Stack"
            attributionStack.axis = .horizontal
            attributionStack.spacing = 8
            attributionStack.alignment = .center
            attributionStack.distribution = .fill
            attributionStack.translatesAutoresizingMaskIntoConstraints = false
            attributionStack.addArrangedSubview(adAttributionLabel)
            attributionStack.addArrangedSubview(adRatingImageView)

            let labelStack = AutoHidingStackView()
            labelStack.accessibilityIdentifier = "Label Stack"
            labelStack.axis = .vertical
            labelStack.spacing = metrics.verticalSpacing
            labelStack.alignment = .leading
            labelStack.distribution = .fill
            labelStack.translatesAutoresizingMaskIntoConstraints = false
            labelStack.addArrangedSubview(adHeadlineLabel)
            labelStack.addArrangedSubview(adSponsorLabel)
            labelStack.addArrangedSubview(attributionStack)
            labelStack.addArrangedSubview(storeStack)

            headlineStack.addArrangedSubview(adIconImageView)
            headlineStack.addArrangedSubview(labelStack)

            let bodyStack = AutoHidingStackView()
            bodyStack.accessibilityIdentifier = "Body Stack"
            bodyStack.axis = .vertical
            bodyStack.spacing = defaultSpacing
            bodyStack.alignment = .leading
            bodyStack.distribution = .fill
            bodyStack.translatesAutoresizingMaskIntoConstraints = false
            bodyStack.addArrangedSubview(headlineStack)
            bodyStack.addArrangedSubview(adBodyLabel)
            bodyStack.addArrangedSubview(actionButton)

            adContainerView.addSubview(contentView)
            adContainerView.addSubview(bodyStack)

            addSubview(adContainerView)

            heightConstraint = NSLayoutConstraint(
                item: contentView,
                attribute: .height,
                relatedBy: .equal,
                toItem: contentView,
                attribute: .width,
                multiplier: currentMultiplier,
                constant: 0
            )

            NSLayoutConstraint.activate([
                adContainerView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                adContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                adContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                adContainerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

                contentView.topAnchor.constraint(equalTo: adContainerView.topAnchor),
                contentView.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),

                bodyStack.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: defaultSpacing),
                bodyStack.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor, constant: 16),
                bodyStack.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor, constant: -16),

                headlineStack.leadingAnchor.constraint(equalTo: bodyStack.leadingAnchor),
                headlineStack.trailingAnchor.constraint(equalTo: bodyStack.trailingAnchor),

                adBodyLabel.leadingAnchor.constraint(equalTo: bodyStack.leadingAnchor),
                adBodyLabel.trailingAnchor.constraint(equalTo: bodyStack.trailingAnchor),

                actionButton.leadingAnchor.constraint(equalTo: bodyStack.leadingAnchor),
                actionButton.trailingAnchor.constraint(equalTo: bodyStack.trailingAnchor),
                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: metrics.ctaMinHeight)
                    .priority(UILayoutPriority(999)),

                adIconImageView.widthAnchor.constraint(equalToConstant: metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),
            ])
        }
    }

    // MARK: - Styling

    extension CustomNativeAdView {

        private func applyStyle() {
            applyBackgroundFill(style.backgrounds.card)
            adContainerView.applyBackgroundFill(style.backgrounds.content)

            adHeadlineLabel.textColor = style.text.headline
            adHeadlineLabel.font = style.text.headlineFont.resolved
            adSponsorLabel.textColor = style.text.sponsor
            adSponsorLabel.font = style.text.sponsorFont.resolved
            adBodyLabel.textColor = style.text.body
            adBodyLabel.font = style.text.bodyFont.resolved

            adAttributionLabel.textColor = style.attribution.text
            adAttributionLabel.backgroundColor = style.attribution.background
            adAttributionLabel.font = style.attribution.font.resolved

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

    // MARK: - Public Methods

    extension CustomNativeAdView {
        public func configure(with nativeAd: NativeAd) {
            // Content is set synchronously; the card height eases at the SwiftUI
            // layer via `.frame(height: store.adHeight)`. (A UIKit transition on
            // `self` here would fight that frame animation on the same layer.)
            applyAspectRatioConstraint(for: nativeAd.mediaContent.aspectRatio)
            updateViewBindings(for: nativeAd)

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

        // MARK: - Update Aspect Ratio

        /// Swaps the media height constraint to match the creative's aspect
        /// ratio. No animation here — the layout change is animated as part of
        /// the coordinated cross-dissolve in `configure`.
        private func applyAspectRatioConstraint(for aspectRatio: CGFloat) {
            guard aspectRatio > 0 else {
                return
            }

            heightConstraint.isActive = false
            heightConstraint = NSLayoutConstraint(
                item: contentView,
                attribute: .height,
                relatedBy: .equal,
                toItem: contentView,
                attribute: .width,
                multiplier: 1.0 / aspectRatio,
                constant: 0
            )
            heightConstraint.isActive = true
            currentMultiplier = 1.0 / aspectRatio
        }

        // MARK: - Update UI Elements

        private func updateUI(with nativeAd: NativeAd) {
            // Synchronous content assignment — the cross-dissolve + layout is
            // driven once by `applyNativeContentUpdate` in `configure`, so this
            // must not start its own per-element animations.
            adIconImageView.image = nativeAd.icon?.image
            adHeadlineLabel.text = nativeAd.headline?.capitalizingFirstLetter()
            adRatingImageView.image = imageOfStars(from: nativeAd.starRating)
            adSponsorLabel.text = nativeAd.advertiser?.capitalizingFirstLetter()
            adStoreLabel.text = nativeAd.store?.capitalized
            adPriceLabel.text = nativeAd.price?.capitalized
            adBodyLabel.text = nativeAd.body?.capitalizingFirstLetter()
            actionButton.setTitle(nativeAd.callToAction?.uppercased(), for: .normal)
            contentView.mediaContent = nativeAd.mediaContent
            contentView.contentMode = .scaleAspectFit
        }

        // MARK: - Bind Views to Native Ad

        private func updateViewBindings(for nativeAd: NativeAd) {
            self.iconView = adIconImageView
            self.headlineView = adHeadlineLabel
            self.advertiserView = adSponsorLabel
            self.starRatingView = adRatingImageView
            self.storeView = adStoreLabel
            self.priceView = adPriceLabel
            self.callToActionView = actionButton
            self.bodyView = adBodyLabel
            self.mediaView = contentView
        }

        // MARK: - Update View Visibility

        private func updateVisibility(for nativeAd: NativeAd) {
            let views: [(UIView?, Any?)] = [
                (iconView, nativeAd.icon?.image),
                (headlineView, nativeAd.headline),
                (advertiserView, nativeAd.advertiser),
                (starRatingView, nativeAd.starRating),
                (bodyView, nativeAd.body),
                (callToActionView, nativeAd.callToAction),
                (storeView, nativeAd.store),
                (priceView, nativeAd.price),
            ]

            // Toggle visibility synchronously — the stack collapse and the
            // resulting height change animate as part of the single
            // cross-dissolve pass in `configure`, not a separate alpha+deferred
            // -isHidden animation (which caused a two-stage height jump).
            views.forEach { view, data in
                view?.isHidden = (data == nil)
                view?.alpha = 1
            }
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

        // MARK: - Calculate Total Height

        /// Width-aware Auto Layout measurement, mirroring the row/compact views
        /// so the SwiftUI wrapper can self-size via `sizeThatFits` (no manual
        /// frame-summing, no `updateAdHeight` feedback loop).
        public func calculateTotalHeight(fittingWidth: CGFloat) -> CGFloat {
            let target = CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height)
            return systemLayoutSizeFitting(
                target,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        }
    }
#endif
